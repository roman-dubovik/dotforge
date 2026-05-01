#!/usr/bin/env bash
# Interactive Brewfile customizer for dotforge.
#
# Usage:
#   customize-brewfile.sh                          # interactive
#   customize-brewfile.sh --archetype full         # non-interactive
#   customize-brewfile.sh --archetype custom       # opens multi-select
#   customize-brewfile.sh --output Brewfile.local
#   customize-brewfile.sh --no-install             # write file but skip install
#
# Archetypes:
#   full        — everything in the canonical Brewfile
#   minimal-dev — CLI + browsers + editors + dev tools (no VPN/media/office)
#   cli-server  — pure CLI, no GUI / no MAS apps
#   custom      — opens a multi-select to pick sections
#
# After selection, runs `brew bundle install --file=<output>`. The chezmoi
# brewfile hook prefers Brewfile.local over Brewfile when both are present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$REPO_ROOT/Brewfile"
OUTPUT="$REPO_ROOT/Brewfile.local"
ARCHETYPE=""
NO_INSTALL=0
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archetype) ARCHETYPE="$2"; shift 2 ;;
        --output)    OUTPUT="$2";    shift 2 ;;
        --brewfile)  BREWFILE="$2";  shift 2 ;;
        --no-install)     NO_INSTALL=1;   shift ;;
        --non-interactive) INTERACTIVE=0; shift ;;
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
    # Show the menu with " (N items, INC|EXC)" suffix; user toggles.
    # gum choose --selected works on the *option strings*, not the option index,
    # so we pre-select option strings that match currently-included sections.
    local options=() selected_csv=""
    local first_selected=1
    for name in "${SECTION_NAMES[@]}"; do
        local idx
        idx="$(section_index "$name")"
        local n_items
        n_items="$(count_items "${SECTION_FILES[$idx]}")"
        local opt="$name ($n_items items)"
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
    if [[ "$ARCHETYPE" == "custom" ]] \
        || gum confirm --default=No "Fine-tune the section selection for archetype '$ARCHETYPE'?"; then
        refine_selection
    fi

    # ── Step 3: preview loop ──
    if (( ${#SELECTED[@]} > 0 )); then
        while gum confirm --default=No "Preview a section before installing?"; do
            local_choice="$(printf "%s\n" "${SELECTED[@]}" | gum choose --header "Section to preview:")"
            [[ -z "$local_choice" ]] && break
            idx="$(section_index "$local_choice")"
            if [[ "$idx" -ge 0 ]]; then
                gum pager < "${SECTION_FILES[$idx]}"
            fi
        done
    fi
fi

# ── Step 4: write output ──

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
} > "$OUTPUT"

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
