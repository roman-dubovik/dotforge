#!/usr/bin/env bash
# dot features — list feature flags with current values and sources.
#
# Usage:
#   scripts/dot-features.sh          # print feature table, exit 0
#   scripts/dot-features.sh --help   # print this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh" 2>/dev/null || {
    log_section() { printf "\n── %s ──\n" "$*"; }
}

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/state.sh"

# ── Argument parsing ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
dot features — list feature flags with current values and sources

Usage:
  dot features             Print all feature flags, their values, and source.
  dot features --help|-h   Print this help.

Sources:
  state.toml   — value comes from ~/.config/dotforge/state.toml (set via `dot apply --enable/--disable` or `bootstrap.sh customize`)
  chezmoi.toml — value comes from ~/.config/chezmoi/chezmoi.toml only
  default      — no persistent state; showing compiled-in default

If state.toml and chezmoi.toml disagree, status shows "DIVERGENT".
EOF
            exit 0
            ;;
        *)
            printf "dot features: unknown argument: %s\n" "$1" >&2
            printf "Run 'dot features --help' for usage.\n" >&2
            exit 2
            ;;
    esac
done

# ── Read sources ──

state_file_path="$(state_file)"
chezmoi_file_path="$(chezmoi_toml_file)"

_state_exists=0
[[ -f "$state_file_path" ]] && _state_exists=1

_chezmoi_exists=0
[[ -f "$chezmoi_file_path" ]] && _chezmoi_exists=1

# Read chezmoi.toml [data.features] section values into indexed arrays.
chezmoi_keys=()
chezmoi_vals=()
if [[ "$_chezmoi_exists" -eq 1 ]]; then
    while IFS="=" read -r ck cv; do
        chezmoi_keys+=("$ck")
        chezmoi_vals+=("$cv")
    done < <(awk '
        /^\[data\.features\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^[[:space:]]*[^#[:space:]]/ {
            n = split($0, parts, "=")
            if (n >= 2) {
                k = parts[1]; gsub(/[[:space:]]/, "", k)
                v = parts[2]
                gsub(/^[[:space:]]+/, "", v)
                gsub(/[[:space:]#].*$/, "", v)
                printf "%s=%s\n", k, v
            }
        }
    ' "$chezmoi_file_path")
fi

# Helper: get chezmoi value for a feature (or "")
_chezmoi_val() {
    local feat="$1" i
    for i in "${!chezmoi_keys[@]}"; do
        [[ "${chezmoi_keys[$i]}" == "$feat" ]] && { printf "%s" "${chezmoi_vals[$i]}"; return; }
    done
    printf ""
}

# ── Print table ──

log_section "Feature flags"
printf "  %-22s %-6s  %-12s  %s\n" "FEATURE" "VALUE" "SOURCE" "STATUS"
printf "  %-22s %-6s  %-12s  %s\n" "-------" "-----" "------" "------"

for i in "${!DOTFORGE_FEATURES[@]}"; do
    feat="${DOTFORGE_FEATURES[$i]}"
    default_val="${DOTFORGE_FEATURE_DEFAULTS[$i]}"

    state_val=""
    if [[ "$_state_exists" -eq 1 ]]; then
        state_val="$(state_get "features.${feat}" 2>/dev/null || printf "")"
    fi

    chezmoi_val="$(_chezmoi_val "$feat")"

    # Determine displayed value, source, status
    if [[ -n "$state_val" ]]; then
        display_val="$state_val"
        source_label="state.toml"
        if [[ -n "$chezmoi_val" && "$chezmoi_val" != "$state_val" ]]; then
            status_label="DIVERGENT"
        else
            status_label="in-sync"
        fi
    elif [[ -n "$chezmoi_val" ]]; then
        display_val="$chezmoi_val"
        source_label="chezmoi.toml"
        status_label="in-sync"
    else
        display_val="$default_val"
        source_label="default"
        status_label=""
    fi

    printf "  %-22s %-6s  %-12s  %s\n" "$feat" "$display_val" "$source_label" "$status_label"
done

printf "\n"
exit 0
