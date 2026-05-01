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
#   sync-brewfile.sh                # interactive promotion
#   sync-brewfile.sh --check        # read-only: show diff and exit
#   sync-brewfile.sh --skip-vscode  # ignore VS Code extensions in the diff
#   sync-brewfile.sh --skip-mas     # ignore Mac App Store apps
#   sync-brewfile.sh --skip-tap     # ignore tap directives

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$REPO_ROOT/Brewfile"
BREWFILE_LOCAL="$REPO_ROOT/Brewfile.local"

CHECK_MODE=0
SKIP_VSCODE=0
SKIP_MAS=0
SKIP_TAP=0
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)         CHECK_MODE=1;     shift ;;
        --skip-vscode)   SKIP_VSCODE=1;    shift ;;
        --skip-mas)      SKIP_MAS=1;       shift ;;
        --skip-tap)      SKIP_TAP=1;       shift ;;
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
