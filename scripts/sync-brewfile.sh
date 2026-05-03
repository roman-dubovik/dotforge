#!/usr/bin/env bash
# Find brew formulas / casks / mas apps / vscode extensions installed locally
# but missing from the tracked Brewfile (and Brewfile.local). For each extra,
# the user picks where to promote it:
#
#   canonical  — append to Brewfile (commits to the repo, rolls out to every
#                machine on the next `chezmoi update`)
#   local      — append to Brewfile.local (gitignored, this machine only)
#   ignore     — skip (will keep appearing on subsequent syncs)
#
# Promoted entries are appended under a clearly marked block at the end of
# the target file. Move them into the proper sections by hand before
# committing.
#
# Inverse direction (tracked but not installed) is reported but not
# auto-removed — it's advisory only. Use `brew bundle install` to install
# them or remove from the Brewfile by hand.
#
# Usage:
#   sync-brewfile.sh                # interactive promotion (brew + /Applications)
#   sync-brewfile.sh --check        # read-only: show diff and exit
#   sync-brewfile.sh --skip-vscode  # ignore VS Code extensions in the diff
#   sync-brewfile.sh --skip-mas     # ignore Mac App Store apps
#   sync-brewfile.sh --skip-tap     # ignore tap directives
#   sync-brewfile.sh --skip-apps    # skip the /Applications scan
#
# /Applications scan: classifies each .app under /Applications as
# tracked (cask / MAS / manual-install block / system) or untracked.
# For each untracked app, prompts to either append a cask line, add a
# manual-install entry with a URL, or ignore.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$REPO_ROOT/Brewfile"
BREWFILE_LOCAL="$REPO_ROOT/Brewfile.local"

CHECK_MODE=0
SKIP_VSCODE=0
SKIP_MAS=0
SKIP_TAP=0
SKIP_APPS=0
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)         CHECK_MODE=1;     shift ;;
        --skip-vscode)   SKIP_VSCODE=1;    shift ;;
        --skip-mas)      SKIP_MAS=1;       shift ;;
        --skip-tap)      SKIP_TAP=1;       shift ;;
        --skip-apps)     SKIP_APPS=1;      shift ;;
        --non-interactive) INTERACTIVE=0;  shift ;;
        --brewfile)      BREWFILE="$2";    shift 2 ;;
        --local)         BREWFILE_LOCAL="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ ! -t 0 ]] && INTERACTIVE=0

command -v brew >/dev/null || { echo "brew is required" >&2; exit 1; }
[[ -f "$BREWFILE" ]] || { echo "Brewfile not found: $BREWFILE" >&2; exit 1; }
if (( INTERACTIVE == 1 )); then
    command -v gum >/dev/null || { echo "gum is required (brew install gum)" >&2; exit 1; }
fi

TMP="$(mktemp -d -t dotforge-sync.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Strip inline comments and trailing whitespace; keep only entry directives.
# Skips the customizer's section markers ("# ── ... ──") which never appear
# in dump output anyway.
extract_entries() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    # 1. keep entry directives only (not section headers, not blank lines)
    # 2. strip inline comments, trailing whitespace, leading whitespace
    # 3. collapse runs of whitespace to a single space (so column-aligned
    #    `mas "X",     id: N` matches `mas "X", id: N` from `brew bundle dump`)
    grep -E '^[[:space:]]*(brew|cask|tap|mas|vscode)[[:space:]]+' "$f" \
        | sed 's/[[:space:]]*#.*$//' \
        | sed 's/[[:space:]]*$//' \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]\{1,\}/ /g'
}

filter_kinds() {
    local input="$1"
    local args=()
    (( SKIP_VSCODE == 1 )) && args+=(-e '^vscode ')
    (( SKIP_MAS    == 1 )) && args+=(-e '^mas ')
    (( SKIP_TAP    == 1 )) && args+=(-e '^tap ')
    if (( ${#args[@]} > 0 )); then
        grep -v "${args[@]}" "$input" || true
    else
        cat "$input"
    fi
}

# ── /Applications scan ──
# Classifies each .app under /Applications and surfaces ones that aren't
# yet covered by the Brewfile (cask), Mac App Store (mas), or the manual
# install comment block.

scan_applications() {
    [[ ! -d /Applications ]] && return 0

    echo ""
    echo "→ Scanning /Applications..."

    local APPS_LOCAL=()
    while IFS= read -r app_path; do
        [[ -n "$app_path" ]] && APPS_LOCAL+=("$(basename "$app_path" .app)")
    done < <(find /Applications -maxdepth 1 -name "*.app" -type d 2>/dev/null | sort)

    if (( ${#APPS_LOCAL[@]} == 0 )); then
        echo "  (no .app bundles found)"
        return 0
    fi

    # MAS-installed app names (from `mas list`)
    local MAS_INSTALLED=()
    if command -v mas >/dev/null 2>&1; then
        while IFS= read -r line; do
            local name
            name="$(echo "$line" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//;s/[[:space:]]*\([^)]*\)[[:space:]]*$//;s/[[:space:]]*$//')"
            [[ -n "$name" ]] && MAS_INSTALLED+=("$name")
        done < <(mas list 2>/dev/null)
    fi

    # Cask names declared in Brewfile (not necessarily brew-installed)
    local CASK_DECLARED=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && CASK_DECLARED+=("$line")
    done < <(grep -E '^[[:space:]]*cask[[:space:]]+"[^"]+"' "$BREWFILE" 2>/dev/null \
        | sed -E 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/' \
        | sed -E 's|.*/||' | sort -u)

    # Build a map from each declared cask's artifact .app name back to its
    # cask name. One batched `brew info --cask --json=v2` call with all
    # declared casks (~1s for 30 casks). 100% accurate — no kebab heuristics.
    # Format: lines of "AppName|cask-name"
    local cask_artifact_map="$TMP/cask-artifacts.txt"
    : > "$cask_artifact_map"
    if (( ${#CASK_DECLARED[@]} > 0 )); then
        echo "  → Resolving cask → app artifact mapping for ${#CASK_DECLARED[@]} declared casks..."
        brew info --cask --json=v2 "${CASK_DECLARED[@]}" 2>/dev/null \
            | jq -r '.casks[] | .token as $t | .artifacts[]? | if type=="object" and (.app // empty | length > 0) then "\(.app[0])|\($t)" else empty end' 2>/dev/null \
            | sed 's/\.app|/|/' \
            > "$cask_artifact_map" || true
    fi

    cask_for_app() {
        local app="$1" cask
        # Exact match against the artifact map (anchored to start of line).
        cask="$(awk -F'|' -v a="$app" '$1 == a { print $2; exit }' "$cask_artifact_map")"
        if [[ -n "$cask" ]]; then
            printf "%s" "$cask"
            return 0
        fi
        # Fallback: kebab-case variants of the app name. Handles pkg-based
        # casks (amneziavpn, displaylink, tailscale-app) whose artifact JSON
        # doesn't expose the .app name and so missed the artifact map.
        local lower kebab dotless compact variant
        lower="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
        kebab="$(echo "$lower" | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
        dotless="$(echo "$lower" | sed 's/\.//g; s/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
        compact="$(echo "$lower" | sed 's/[^a-z0-9]//g')"
        for variant in "$kebab" "$dotless" "$compact" "${kebab}-app" "${kebab}-desktop" "${kebab}-community"; do
            if in_arr "$variant" "${CASK_DECLARED[@]+"${CASK_DECLARED[@]}"}"; then
                printf "%s" "$variant"
                return 0
            fi
        done
        return 0   # always succeed; empty stdout = no match
    }

    # Prefix-tolerant manual-name match (handles "Movavi Video Editor 25"
    # against the cleaner "Movavi Video Editor" in the manual block, and
    # vice versa for "stagewise" → "stagewise (Pre-Release)").
    matches_manual() {
        local app="$1" m
        for m in "${MANUAL_NAMES[@]+"${MANUAL_NAMES[@]}"}"; do
            [[ -z "$m" ]] && continue
            if [[ "$app" == "$m" ]] \
               || [[ "$app" == "$m"\ * ]] \
               || [[ "$m" == "$app"\ * ]]; then
                return 0
            fi
        done
        return 1
    }

    # MAS names declared in Brewfile (`mas "Name", id: ...`)
    local MAS_DECLARED=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && MAS_DECLARED+=("$line")
    done < <(grep -E '^[[:space:]]*mas[[:space:]]+"[^"]+"' "$BREWFILE" 2>/dev/null \
        | sed -E 's/^[[:space:]]*mas[[:space:]]+"([^"]+)".*/\1/' | sort -u)

    # Cask-installed app artifact names (the .app file each installed cask drops).
    # One batched `brew info --cask --json=v2` call across all installed casks.
    local CASK_INSTALLED_APPS=()
    local installed_casks=()
    while IFS= read -r cask; do
        [[ -n "$cask" ]] && installed_casks+=("$cask")
    done < <(brew list --cask 2>/dev/null || true)
    if (( ${#installed_casks[@]} > 0 )); then
        local artifacts
        artifacts="$(brew info --cask --json=v2 "${installed_casks[@]}" 2>/dev/null \
            | jq -r '.casks[].artifacts[]? | if type=="object" and (.app // empty | length > 0) then .app[]? else empty end' 2>/dev/null || true)"
        while IFS= read -r a; do
            [[ -z "$a" ]] && continue
            CASK_INSTALLED_APPS+=("${a%.app}")
        done <<< "$artifacts"
    fi

    # Manual-install names from Brewfile comment block
    local MANUAL_NAMES=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && MANUAL_NAMES+=("$line")
    done < <(awk '
        /^# ── Manual install/{ in_block=1; next }
        /^# ──/ && in_block { in_block=0 }
        in_block && /^#[[:space:]]+-[[:space:]]/ {
            sub(/^#[[:space:]]+-[[:space:]]+/, "")
            sub(/[[:space:]]+https?:.*$/, "")
            sub(/[[:space:]]+\(.*$/, "")
            sub(/[[:space:]]+TBD.*$/, "")
            sub(/[[:space:]]+$/, "")
            if (length($0) > 0) print
        }
    ' "$BREWFILE" 2>/dev/null | sort -u)

    # Common Apple-bundled / system apps (not in MAS) — skip these
    local SYSTEM_NAMES=(Safari Mail Calendar Notes Reminders Maps FaceTime Messages Photos TextEdit Calculator Stickies "Voice Memos" Music TV Podcasts News Books Stocks Weather Home Shortcuts "Find My" "Image Capture" "System Information" "System Settings" "System Preferences" "App Store" "Time Machine" Dictionary "Photo Booth" "QuickTime Player" Preview Automator "Script Editor" Chess "Font Book" "Disk Utility" "Activity Monitor" Console Terminal "Migration Assistant" Utilities)

    local UNTRACKED=()
    local NEEDS_ADOPT=()
    local n_cask_installed=0 n_cask_declared=0 n_mas=0 n_manual=0 n_system=0

    in_arr() {
        local needle="$1"; shift
        local h
        for h in "$@"; do
            [[ "$h" == "$needle" ]] && return 0
        done
        return 1
    }

    NEEDS_ADOPT_CASKS=()  # cask names to adopt

    for app in "${APPS_LOCAL[@]}"; do
        local matched_cask
        if in_arr "$app" "${CASK_INSTALLED_APPS[@]+"${CASK_INSTALLED_APPS[@]}"}"; then
            # Brew-installed cask → fully tracked
            n_cask_installed=$((n_cask_installed+1))
            continue
        fi
        matched_cask="$(cask_for_app "$app")"
        if [[ -n "$matched_cask" ]]; then
            # Declared in Brewfile but not adopted — needs --adopt
            n_cask_declared=$((n_cask_declared+1))
            NEEDS_ADOPT+=("$app")
            NEEDS_ADOPT_CASKS+=("$matched_cask")
            continue
        fi
        if in_arr "$app" "${MAS_INSTALLED[@]+"${MAS_INSTALLED[@]}"}"; then
            n_mas=$((n_mas+1))
        elif in_arr "$app" "${MAS_DECLARED[@]+"${MAS_DECLARED[@]}"}"; then
            n_mas=$((n_mas+1))
        elif matches_manual "$app"; then
            n_manual=$((n_manual+1))
        elif in_arr "$app" "${SYSTEM_NAMES[@]}"; then
            n_system=$((n_system+1))
        else
            UNTRACKED+=("$app")
        fi
    done

    echo ""
    echo "── /Applications scan ──"
    printf "  Tracked: %d cask-installed, %d cask-declared (needs adopt), %d MAS, %d manual, %d system\n" \
        "$n_cask_installed" "$n_cask_declared" "$n_mas" "$n_manual" "$n_system"

    if (( ${#NEEDS_ADOPT[@]} > 0 )); then
        echo ""
        echo "  ${#NEEDS_ADOPT[@]} app(s) declared as cask in Brewfile but installed manually:"
        local i
        for ((i = 0; i < ${#NEEDS_ADOPT[@]}; i++)); do
            printf "    • %-30s (cask: %s)\n" "${NEEDS_ADOPT[i]}" "${NEEDS_ADOPT_CASKS[i]}"
        done
        echo ""
        echo "  Adopt them so brew tracks updates (no reinstall):"
        echo "    brew install --cask --adopt $(printf "%s " "${NEEDS_ADOPT_CASKS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
    fi

    if (( ${#UNTRACKED[@]} == 0 )); then
        echo "  ✓ Nothing untracked."
        return 0
    fi

    echo ""
    echo "  Untracked (${#UNTRACKED[@]}):"
    for a in "${UNTRACKED[@]}"; do
        echo "    ? $a"
    done

    if (( CHECK_MODE == 1 )) || (( INTERACTIVE == 0 )); then
        echo ""
        echo "  Run interactively (no --check) to promote."
        return 0
    fi

    echo ""
    if ! gum confirm --default=Yes "Promote untracked apps now (cask / manual+URL / ignore)?"; then
        return 0
    fi

    local manual_buffer="$TMP/manual-additions.txt"
    : > "$manual_buffer"

    local n_to_cask=0 n_to_manual=0 n_app_ignored=0

    for app in "${UNTRACKED[@]}"; do
        local cask_guess cask_exists=0 choice
        cask_guess="$(echo "$app" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
        if brew --cask info "$cask_guess" >/dev/null 2>&1; then
            cask_exists=1
        fi

        echo ""
        if (( cask_exists == 1 )); then
            choice="$(gum choose --header "Untracked: $app  (cask candidate: $cask_guess)" \
                "cask    — append cask \"$cask_guess\" to Brewfile (rolls out everywhere)" \
                "manual  — add to manual-install block with a URL" \
                "ignore  — skip (will reappear next sync)")"
        else
            choice="$(gum choose --header "Untracked: $app  (no cask matching '$cask_guess')" \
                "manual  — add to manual-install block with a URL" \
                "search  — try a different cask name" \
                "ignore  — skip")"
        fi

        case "$choice" in
            cask*)
                printf "\n# Promoted from /Applications scan on %s — %s\ncask \"%s\"\n" \
                    "$(date '+%Y-%m-%d %H:%M')" "$app" "$cask_guess" >> "$BREWFILE"
                echo "  ✓ Appended cask \"$cask_guess\""
                echo "    Tip: 'brew install --cask --adopt $cask_guess' to register the existing app."
                n_to_cask=$((n_to_cask+1))
                ;;
            search*)
                local manual_cask
                manual_cask="$(gum input --prompt "Cask name to use: " --value "$cask_guess")"
                if [[ -n "$manual_cask" ]] && brew --cask info "$manual_cask" >/dev/null 2>&1; then
                    printf "\n# Promoted from /Applications scan on %s — %s\ncask \"%s\"\n" \
                        "$(date '+%Y-%m-%d %H:%M')" "$app" "$manual_cask" >> "$BREWFILE"
                    echo "  ✓ Appended cask \"$manual_cask\""
                    n_to_cask=$((n_to_cask+1))
                else
                    echo "  ✗ '$manual_cask' is not a valid cask. Skipping."
                    n_app_ignored=$((n_app_ignored+1))
                fi
                ;;
            manual*)
                local url
                url="$(gum input --prompt "Source URL for $app (or leave blank): ")"
                if [[ -n "$url" ]]; then
                    printf "#   - %-25s %s\n" "$app" "$url" >> "$manual_buffer"
                else
                    printf "#   - %-25s (source URL TBD — please update)\n" "$app" >> "$manual_buffer"
                fi
                echo "  ✓ Buffered manual entry for $app"
                n_to_manual=$((n_to_manual+1))
                ;;
            *)  echo "  ⏭ Skipped"; n_app_ignored=$((n_app_ignored+1)) ;;
        esac
    done

    if [[ -s "$manual_buffer" ]]; then
        {
            printf "\n# ── Promoted from /Applications scan on %s (Manual install — review and merge above) ──\n" "$(date '+%Y-%m-%d %H:%M')"
            printf "# Move these into the existing '── Manual install ──' block before committing.\n"
            cat "$manual_buffer"
        } >> "$BREWFILE"
    fi

    echo ""
    echo "  /Applications results: cask=$n_to_cask  manual=$n_to_manual  ignored=$n_app_ignored"
}

# ── Capture state ──

echo "→ Dumping installed state via brew bundle..."
brew bundle dump --force --file="$TMP/installed-raw.txt" >/dev/null 2>&1
extract_entries "$TMP/installed-raw.txt" | sort -u > "$TMP/installed.txt.unfiltered"
filter_kinds "$TMP/installed.txt.unfiltered" | sort -u > "$TMP/installed.txt"

echo "→ Reading tracked Brewfiles..."
{
    extract_entries "$BREWFILE"
    extract_entries "$BREWFILE_LOCAL"
} | sort -u > "$TMP/tracked.txt.unfiltered"
filter_kinds "$TMP/tracked.txt.unfiltered" | sort -u > "$TMP/tracked.txt"

# ── Diff ──

comm -23 "$TMP/installed.txt" "$TMP/tracked.txt" > "$TMP/extras.txt"
comm -13 "$TMP/installed.txt" "$TMP/tracked.txt" > "$TMP/missing.txt"

# ── Pre-fetch descriptions for nicer prompts ──
# brew desc accepts multiple names; we batch formulas and casks separately
# to keep one or two calls instead of N per-entry.

fetch_descriptions() {
    local list_file="$1" out_file="$2"
    : > "$out_file"
    [[ ! -s "$list_file" ]] && return 0

    local formulas=() casks=()
    while IFS= read -r entry; do
        if [[ "$entry" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            formulas+=("${BASH_REMATCH[1]}")
        elif [[ "$entry" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            casks+=("${BASH_REMATCH[1]}")
        fi
    done < "$list_file"

    # `brew desc <names...>` returns "name: description" per line; we capture
    # both formula and cask runs into the same out_file.
    if (( ${#formulas[@]} > 0 )); then
        brew desc --formula "${formulas[@]}" 2>/dev/null \
            | sed 's/^/F:/' >> "$out_file" || true
    fi
    if (( ${#casks[@]} > 0 )); then
        brew desc --cask "${casks[@]}" 2>/dev/null \
            | sed 's/^/C:/' >> "$out_file" || true
    fi
}

# Returns a short description for an entry line (or empty string).
desc_for() {
    local entry="$1" cache="$2"
    [[ -s "$cache" ]] || { printf "%s" ""; return; }
    if [[ "$entry" =~ ^(brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
        local kind="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}"
        local prefix="F"
        [[ "$kind" == "cask" ]] && prefix="C"
        # Match exactly "P:name: ..."; brew desc lines look like
        # "name: description" so we anchor name.
        grep -F "${prefix}:${name}: " "$cache" \
            | head -1 \
            | sed "s/^${prefix}:${name}: //"
    elif [[ "$entry" =~ ^mas[[:space:]] ]]; then
        printf "%s" "Mac App Store app"
    elif [[ "$entry" =~ ^tap[[:space:]] ]]; then
        printf "%s" "Homebrew tap"
    elif [[ "$entry" =~ ^vscode[[:space:]] ]]; then
        printf "%s" "VS Code extension"
    fi
}

echo "→ Fetching descriptions for extras and missing..."
fetch_descriptions "$TMP/extras.txt"  "$TMP/desc-extras.txt"
fetch_descriptions "$TMP/missing.txt" "$TMP/desc-missing.txt"

n_extras="$(wc -l < "$TMP/extras.txt" | tr -d ' ')"
n_missing="$(wc -l < "$TMP/missing.txt" | tr -d ' ')"

if (( n_extras == 0 && n_missing == 0 )); then
    echo "✓ Brewfile is in sync with installed state."
    exit 0
fi

render_with_desc() {
    local list_file="$1" cache_file="$2"
    while IFS= read -r entry; do
        local d
        d="$(desc_for "$entry" "$cache_file")"
        if [[ -n "$d" ]]; then
            printf "  %s — %s\n" "$entry" "$d"
        else
            printf "  %s\n" "$entry"
        fi
    done < "$list_file"
}

echo ""
echo "── EXTRAS ($n_extras) — installed locally, not in Brewfile / Brewfile.local ──"
if (( n_extras > 0 )); then
    render_with_desc "$TMP/extras.txt" "$TMP/desc-extras.txt"
else
    echo "  (none)"
fi

echo ""
echo "── MISSING ($n_missing) — in Brewfile, not installed ──"
if (( n_missing > 0 )); then
    render_with_desc "$TMP/missing.txt" "$TMP/desc-missing.txt"
else
    echo "  (none)"
fi

if (( CHECK_MODE == 1 )); then
    if (( SKIP_APPS == 0 )); then
        scan_applications
    fi
    exit 0
fi

# ── Promotion ──

if (( n_extras == 0 )); then
    echo ""
    echo "Nothing to promote (no extras)."
    exit 0
fi

if (( INTERACTIVE == 0 )); then
    echo ""
    echo "Non-interactive mode: pass extras to canonical Brewfile by hand."
    echo "Re-run interactively to use the gum prompt."
    exit 0
fi

# Group promotions per target file so we append once with a header.
: > "$TMP/append-canonical.txt"
: > "$TMP/append-local.txt"

n_canon=0
n_local=0
n_ignore=0

i=0
while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    i=$((i+1))
    desc="$(desc_for "$entry" "$TMP/desc-extras.txt")"
    header="[$i/$n_extras] $entry"
    [[ -n "$desc" ]] && header="$header — $desc"
    echo ""
    target="$(gum choose --header "$header" \
        "canonical — append to Brewfile (commits to repo, rolls out everywhere)" \
        "local     — append to Brewfile.local (this machine only, gitignored)" \
        "ignore    — skip (will reappear on next sync)")"
    case "$target" in
        canonical*) printf "%s\n" "$entry" >> "$TMP/append-canonical.txt"; n_canon=$((n_canon+1)) ;;
        local*)     printf "%s\n" "$entry" >> "$TMP/append-local.txt";     n_local=$((n_local+1)) ;;
        *)          n_ignore=$((n_ignore+1)) ;;
    esac
done < "$TMP/extras.txt"

apply_appends() {
    local target_file="$1" append_file="$2" label="$3"
    [[ ! -s "$append_file" ]] && return 0
    {
        printf "\n# ── Promoted from sync-brewfile.sh on %s (%s) ──\n" "$(date '+%Y-%m-%d %H:%M')" "$label"
        printf "# Move these into the proper section headers above before committing.\n"
        cat "$append_file"
    } >> "$target_file"
    echo "✓ Appended $(wc -l < "$append_file" | tr -d ' ') entries to $target_file"
}

echo ""
apply_appends "$BREWFILE"       "$TMP/append-canonical.txt" "canonical"
apply_appends "$BREWFILE_LOCAL" "$TMP/append-local.txt"     "local"

echo ""
echo "Summary: canonical=$n_canon  local=$n_local  ignored=$n_ignore"

# ── Show diff and offer to commit ──

if [[ $n_canon -gt 0 ]] && command -v git >/dev/null && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo ""
    echo "── git diff Brewfile ──"
    git -C "$REPO_ROOT" --no-pager diff -- Brewfile

    if gum confirm --default=No "Stage and commit Brewfile now?"; then
        commit_msg="$(gum input --header "Commit message:" --value "feat(Brewfile): promote $n_canon entries from sync")"
        if [[ -n "$commit_msg" ]]; then
            git -C "$REPO_ROOT" add Brewfile
            git -C "$REPO_ROOT" commit -m "$commit_msg"
            echo "✓ Committed. Push manually when ready: git push"
        else
            echo "Skipped (empty commit message)."
        fi
    else
        echo "Skipped commit. Inspect $BREWFILE manually before committing."
    fi
fi

if [[ $n_missing -gt 0 ]]; then
    echo ""
    echo "Reminder: $n_missing tracked entries are not installed."
    echo "Run 'brew bundle install --file=Brewfile' to install them, or"
    echo "remove the unwanted ones from $BREWFILE by hand."
fi

if (( SKIP_APPS == 0 )); then
    scan_applications
fi
