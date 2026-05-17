#!/usr/bin/env bash
# Interactive Brewfile customizer for dotforge.
#
# Usage:
#   customize-brewfile.sh                          # interactive
#   customize-brewfile.sh --archetype full         # non-interactive
#   customize-brewfile.sh --archetype custom       # opens multi-select
#   customize-brewfile.sh --output Brewfile.local
#   customize-brewfile.sh --no-install             # write file but skip install
#   customize-brewfile.sh --enable=<feature>       # force-include a feature
#   customize-brewfile.sh --disable=<feature>      # force-exclude a feature
#
# Archetypes:
#   full        — everything in the canonical Brewfile
#   minimal-dev — CLI + browsers + editors + dev tools (no VPN/media/office)
#   cli-server  — pure CLI, no GUI / no MAS apps
#   custom      — opens a multi-select to pick sections
#
# Feature flags (applied after section selection):
#   docker_desktop  — cask "docker-desktop"                          (default: enabled)
#   ai_assistants   — cask "claude", cask "chatgpt"                  (default: enabled)
#   vpn_suite       — tunnelblick, amneziavpn, anydesk, displaylink,
#                     termius, windows-app                            (default: enabled)
#   office_suite    — mas Microsoft Word/Excel/PowerPoint             (default: disabled)
#   media_tools     — brew ffmpeg, yt-dlp, pandoc, tectonic           (default: enabled)
#   design_tools    — cask "drawio"                                   (default: enabled)
#
# After selection, runs `brew bundle install --file=<output>`. The chezmoi
# brewfile hook prefers Brewfile.local over Brewfile when both are present.

set -euo pipefail

# ── Feature → pattern map (bash 3.2 compat: parallel indexed arrays, no -A) ──
# Each FEATURE_PATTERNS[i] is an ERE matched against Brewfile lines.
# Order must match FEATURE_NAMES[]; both arrays are zero-indexed.
FEATURE_NAMES=(
    "docker_desktop"
    "ai_assistants"
    "vpn_suite"
    "office_suite"
    "media_tools"
    "design_tools"
)
FEATURE_PATTERNS=(
    '^cask "docker-desktop"$'
    '^cask "(claude|chatgpt)"$'
    '^cask "(tunnelblick|amneziavpn|anydesk|displaylink|termius|windows-app)"'
    '^mas "Microsoft (Word|Excel|PowerPoint)"'
    '^brew "(ffmpeg|yt-dlp|pandoc|tectonic)"$'
    '^cask "drawio"$'
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$REPO_ROOT/Brewfile"
OUTPUT="$REPO_ROOT/Brewfile.local"
ARCHETYPE=""
NO_INSTALL=0
INTERACTIVE=1
ENABLED_FEATURES=()
DISABLED_FEATURES=()

# Validate that a feature name is in FEATURE_NAMES[]; exit 2 if unknown.
validate_feature() {
    local f="$1" n
    for n in "${FEATURE_NAMES[@]}"; do
        [[ "$n" == "$f" ]] && return 0
    done
    printf "error: unknown feature '%s'. Supported: %s\n" "$f" "${FEATURE_NAMES[*]}" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archetype)
            ARCHETYPE="$2"
            if [[ "$ARCHETYPE" == "custom" ]]; then
                echo "--archetype custom is not supported via CLI (custom requires interactive selection)" >&2
                exit 2
            fi
            shift 2 ;;
        --output)    OUTPUT="$2";    shift 2 ;;
        --brewfile)  BREWFILE="$2";  shift 2 ;;
        --no-install)     NO_INSTALL=1;   shift ;;
        --non-interactive) INTERACTIVE=0; shift ;;
        --enable=*)
            _feat="${1#--enable=}"
            validate_feature "$_feat"
            ENABLED_FEATURES+=("$_feat")
            shift ;;
        --disable=*)
            _feat="${1#--disable=}"
            validate_feature "$_feat"
            DISABLED_FEATURES+=("$_feat")
            shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Auto-detect non-interactive when stdin is not a TTY (e.g. piped from CI).
if [[ ! -t 0 ]]; then
    INTERACTIVE=0
fi

[[ -f "$BREWFILE" ]] || { echo "Brewfile not found: $BREWFILE" >&2; exit 1; }
command -v gum >/dev/null 2>&1 || { echo "gum is required (brew install gum)" >&2; exit 1; }

# ── Parse Brewfile into sections ──
# Sections are delimited by lines like "# ── Title ──". The trailing
# "# ── Manual install ──" block is informational comments only — we keep
# it out of the selectable list (always omitted from output).

SECTION_NAMES=()
SECTION_FILES=()

TMPDIR_LOCAL="$(mktemp -d -t dotforge-brewfile.XXXXXX)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

current_name=""
current_file=""
section_idx=0

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^#[[:space:]]──[[:space:]](.+)[[:space:]]──[[:space:]]*$ ]]; then
        section_title="${BASH_REMATCH[1]}"
        if [[ "$section_title" == *"Manual install"* ]]; then
            current_name=""
            continue
        fi
        current_name="$section_title"
        current_file="$TMPDIR_LOCAL/$(printf "%03d" "$section_idx")-section.txt"
        SECTION_NAMES+=("$current_name")
        SECTION_FILES+=("$current_file")
        : > "$current_file"
        section_idx=$((section_idx+1))
        continue
    fi
    if [[ -n "$current_name" ]]; then
        printf "%s\n" "$line" >> "$current_file"
    fi
done < "$BREWFILE"

if (( ${#SECTION_NAMES[@]} == 0 )); then
    echo "Brewfile has no '# ── Title ──' section markers." >&2
    echo "Cannot customize. Run 'brew bundle install' directly." >&2
    exit 1
fi

count_items() {
    local f="$1"
    grep -cE '^[[:space:]]*(brew|cask|tap|mas)[[:space:]]+' "$f" || true
}

# Show first 3 entry names (without `brew "..."` syntax) as a one-line hint.
peek_items() {
    local f="$1" hint
    hint="$(grep -E '^[[:space:]]*(brew|cask|mas)[[:space:]]+' "$f" \
        | head -3 \
        | sed -E 's/^[[:space:]]*(brew|cask|mas)[[:space:]]+"([^"]+)".*/\2/' \
        | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"
    if [[ "$(grep -cE '^[[:space:]]*(brew|cask|mas)[[:space:]]+' "$f")" -gt 3 ]]; then
        hint="$hint, …"
    fi
    printf "%s" "$hint"
}

# Cache of "name|description" lines, lazily populated.
DESC_CACHE="$TMPDIR_LOCAL/desc.txt"
: > "$DESC_CACHE"

build_desc_cache() {
    local formulas=() casks=()
    local f
    for f in "${SECTION_FILES[@]}"; do
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*brew[[:space:]]+\"([^\"]+)\" ]]; then
                formulas+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*cask[[:space:]]+\"([^\"]+)\" ]]; then
                casks+=("${BASH_REMATCH[1]}")
            fi
        done < "$f"
    done
    if (( ${#formulas[@]} > 0 )); then
        brew desc --formula "${formulas[@]}" 2>/dev/null \
            | sed -E 's/^([^:]+): /F\|\1\|/' >> "$DESC_CACHE" || true
    fi
    if (( ${#casks[@]} > 0 )); then
        brew desc --cask "${casks[@]}" 2>/dev/null \
            | sed -E 's/^([^:]+): /C\|\1\|/' >> "$DESC_CACHE" || true
    fi
}

# Lookup: given a Brewfile line, return its description annotation.
desc_for_line() {
    local line="$1" name prefix
    if [[ "$line" =~ ^[[:space:]]*brew[[:space:]]+\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"; prefix="F"
    elif [[ "$line" =~ ^[[:space:]]*cask[[:space:]]+\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"; prefix="C"
    else
        return 0
    fi
    grep -F "${prefix}|${name}|" "$DESC_CACHE" | head -1 | cut -d'|' -f3-
}

# Render a section file with an inline description comment per entry.
render_with_descriptions() {
    local f="$1"
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(brew|cask)[[:space:]]+\" ]]; then
            local d
            d="$(desc_for_line "$line")"
            if [[ -n "$d" ]]; then
                printf "%-50s # %s\n" "$line" "$d"
            else
                printf "%s\n" "$line"
            fi
        else
            printf "%s\n" "$line"
        fi
    done < "$f"
}

# Returns the index of $1 in SECTION_NAMES, or -1.
section_index() {
    local target="$1" i=0
    for n in "${SECTION_NAMES[@]}"; do
        if [[ "$n" == "$target" ]]; then
            printf "%d" "$i"
            return 0
        fi
        i=$((i+1))
    done
    printf "%d" -1
}

# ── Archetype presets ──

archetype_default_sections() {
    case "$1" in
        full)
            printf "%s\n" "${SECTION_NAMES[@]}"
            ;;
        minimal-dev)
            cat <<'EOF'
Taps
CLI essentials
Bootstrap deps
Languages / runtimes
Cloud / dev tooling
Media / docs
Fonts
Browsers
Terminals & editors
Dev utilities
AI assistants (desktop)
Productivity / window mgmt
EOF
            ;;
        cli-server)
            cat <<'EOF'
Taps
CLI essentials
Bootstrap deps
Languages / runtimes
Cloud / dev tooling
Media / docs
EOF
            ;;
        custom)
            # Custom starts with all sections selected, then user fine-tunes.
            printf "%s\n" "${SECTION_NAMES[@]}"
            ;;
    esac
}

# ── Step 1: archetype ──

if [[ -z "$ARCHETYPE" ]]; then
    if (( INTERACTIVE == 0 )); then
        echo "--archetype required in non-interactive mode" >&2
        exit 2
    fi
    ARCHETYPE="$(gum choose --header "dotforge Brewfile customizer — pick an archetype:" \
        full \
        minimal-dev \
        cli-server \
        custom)"
fi

case "$ARCHETYPE" in
    full|minimal-dev|cli-server|custom) ;;
    *) echo "Unknown archetype: $ARCHETYPE" >&2; exit 1 ;;
esac

# Build initial SELECTED from archetype
SELECTED=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    SELECTED+=("$line")
done < <(archetype_default_sections "$ARCHETYPE")

# Drop entries not in SECTION_NAMES (e.g. preset typo or Brewfile changed).
TMP_VALID=()
for s in "${SELECTED[@]}"; do
    idx="$(section_index "$s")"
    if [[ "$idx" -ge 0 ]]; then
        TMP_VALID+=("$s")
    fi
done
SELECTED=("${TMP_VALID[@]}")

# ── Step 2: fine-tune (always for custom; offered for the others) ──

refine_selection() {
    # Show the menu with " (N items: x, y, z, …)" suffix; user toggles via space.
    # gum choose --selected works on the *option strings*, not the option index,
    # so we pre-select option strings that match currently-included sections.
    local options=() selected_csv=""
    local first_selected=1
    for name in "${SECTION_NAMES[@]}"; do
        local idx
        idx="$(section_index "$name")"
        local n_items hint
        n_items="$(count_items "${SECTION_FILES[$idx]}")"
        hint="$(peek_items "${SECTION_FILES[$idx]}")"
        local opt
        if [[ -n "$hint" ]]; then
            opt="$name ($n_items items: $hint)"
        else
            opt="$name ($n_items items)"
        fi
        options+=("$opt")
        if printf '%s\n' "${SELECTED[@]}" | grep -qFx "$name"; then
            if (( first_selected == 1 )); then
                selected_csv="$opt"
                first_selected=0
            else
                selected_csv="$selected_csv,$opt"
            fi
        fi
    done

    local chosen
    chosen="$(printf "%s\n" "${options[@]}" | gum choose \
        --no-limit \
        --selected="$selected_csv" \
        --header "Toggle sections (space toggle, enter confirm):" \
        --height 20)"

    SELECTED=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        SELECTED+=("${line% (*}")
    done <<< "$chosen"
}

if (( INTERACTIVE == 1 )); then
    # Pre-fetch descriptions once (slow on cold cache; ~3-5s). Used by both the
    # multi-select hint and the pager preview.
    echo "→ Fetching package descriptions..."
    build_desc_cache

    if [[ "$ARCHETYPE" == "custom" ]] \
        || gum confirm --default=No "Fine-tune the section selection for archetype '$ARCHETYPE'?"; then
        refine_selection
    fi

    # ── Step 3: preview loop ──
    if (( ${#SELECTED[@]} > 0 )); then
        while gum confirm --default=No "Preview a section (with descriptions) before installing?"; do
            local_choice="$(printf "%s\n" "${SELECTED[@]}" | gum choose --header "Section to preview:")"
            [[ -z "$local_choice" ]] && break
            idx="$(section_index "$local_choice")"
            if [[ "$idx" -ge 0 ]]; then
                render_with_descriptions "${SECTION_FILES[$idx]}" | gum pager
            fi
        done
    fi
fi

# ── Feature filter ──
# Applies --disable and --enable transforms to a collected-output file in-place.
# If a feature appears in both --enable and --disable, enable wins (applied last).
#
# Args: $1 = file to filter in place (modified atomically via .tmp sibling).
apply_feature_filter() {
    local target_file="$1" i feature pattern

    # Apply disabled features: remove lines matching pattern.
    if (( ${#DISABLED_FEATURES[@]} > 0 )); then
        for feature in "${DISABLED_FEATURES[@]}"; do
            for i in "${!FEATURE_NAMES[@]}"; do
                if [[ "${FEATURE_NAMES[$i]}" == "$feature" ]]; then
                    pattern="${FEATURE_PATTERNS[$i]}"
                    grep -vE "$pattern" "$target_file" > "${target_file}.tmp" \
                        && mv "${target_file}.tmp" "$target_file"
                    break
                fi
            done
        done
    fi

    # Apply enabled features: add matching lines from canonical Brewfile if absent.
    # Lines are appended at the end of the file — brew bundle ignores section order.
    if (( ${#ENABLED_FEATURES[@]} > 0 )); then
        for feature in "${ENABLED_FEATURES[@]}"; do
            for i in "${!FEATURE_NAMES[@]}"; do
                if [[ "${FEATURE_NAMES[$i]}" == "$feature" ]]; then
                    pattern="${FEATURE_PATTERNS[$i]}"
                    while IFS= read -r line; do
                        if ! grep -qFx "$line" "$target_file"; then
                            printf "%s\n" "$line" >> "$target_file"
                        fi
                    done < <(grep -E "$pattern" "$BREWFILE")
                    break
                fi
            done
        done
    fi
}

# ── Step 4: write output ──

OUTPUT_TMP="$(mktemp "${OUTPUT}.tmp.XXXXXX")"
trap 'rm -rf "$TMPDIR_LOCAL"; rm -f "$OUTPUT_TMP" "${OUTPUT_TMP}.tmp"' EXIT
{
    printf "# Generated by scripts/customize-brewfile.sh on %s\n" "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf "# Archetype: %s\n" "$ARCHETYPE"
    printf "# Selected sections (%d of %d):\n" "${#SELECTED[@]}" "${#SECTION_NAMES[@]}"
    for s in "${SELECTED[@]}"; do
        printf "#   - %s\n" "$s"
    done
    printf "\n"

    for s in "${SELECTED[@]}"; do
        idx="$(section_index "$s")"
        printf "# ── %s ──\n" "$s"
        cat "${SECTION_FILES[$idx]}"
        printf "\n"
    done
} > "$OUTPUT_TMP"

# Apply feature filters (if any) before atomic rename.
if (( ${#ENABLED_FEATURES[@]} > 0 )) || (( ${#DISABLED_FEATURES[@]} > 0 )); then
    apply_feature_filter "$OUTPUT_TMP"
fi

mv -f "$OUTPUT_TMP" "$OUTPUT"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT  # disarm OUTPUT_TMP cleanup now that output is in place

n_total="$(grep -cE '^[[:space:]]*(brew|cask|tap|mas)[[:space:]]+' "$OUTPUT" || true)"

# ── Step 5: confirm + install ──

gum style --foreground 212 --margin "1 0" "Wrote $n_total entries to $OUTPUT"
gum style "Sections: ${#SELECTED[@]} of ${#SECTION_NAMES[@]} included"

if (( NO_INSTALL == 1 )); then
    gum style "Skipped install (--no-install). Run later:"
    gum style "  brew bundle install --file=$OUTPUT"
    exit 0
fi

if (( INTERACTIVE == 0 )); then
    brew bundle install --file="$OUTPUT" --no-lock
elif gum confirm --default=Yes "Run 'brew bundle install --file=$(basename "$OUTPUT")' now?"; then
    brew bundle install --file="$OUTPUT" --no-lock
else
    gum style "Skipped install. Run later:"
    gum style "  brew bundle install --file=$OUTPUT"
fi
