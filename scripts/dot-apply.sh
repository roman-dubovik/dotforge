#!/usr/bin/env bash
# dot apply — run chezmoi apply with before/after doctor diff.
#
# Usage:
#   scripts/dot-apply.sh              # apply + show before/after doctor delta
#   scripts/dot-apply.sh --dry-run    # show pending chezmoi diff (no mutations)
#   scripts/dot-apply.sh --help|-h    # print this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh" 2>/dev/null || {
    # fallback no-op loggers if lib/log.sh missing (shouldn't happen in normal flow)
    log_info()    { printf "%s\n" "$*"; }
    log_ok()      { printf "✓ %s\n" "$*"; }
    log_error()   { printf "ERROR: %s\n" "$*" >&2; }
    log_section() { printf "\n── %s ──\n" "$*"; }
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            cat <<'EOF'
dot apply — apply chezmoi dotfiles and show before/after doctor diff

Usage:
  dot apply              Apply chezmoi and show before/after doctor diff.
                         Exit code matches post-apply doctor (0 = clean).
  dot apply --dry-run    Show pending chezmoi diff without mutating anything.
                         Equivalent to: chezmoi diff
  dot apply --help|-h    Print this help.

Notes:
  - Run 'dot doctor' first to inspect current drift.
  - '--check=brewfile' selective apply is not supported (chezmoi limitation).
EOF
            exit 0
            ;;
        *)
            printf "dot apply: unknown argument: %s\n" "$1" >&2
            printf "Run 'dot apply --help' for usage.\n" >&2
            exit 2
            ;;
    esac
done

# ── Dry-run branch (exec replaces process; trap not needed — tmp files not yet created) ──

if [[ "$DRY_RUN" -eq 1 ]]; then
    log_section "dot apply --dry-run"
    log_info "Showing pending chezmoi diff (no changes will be made)…"
    exec chezmoi diff
fi

# ── Normal apply ──

BEFORE="/tmp/dot-doctor.before.$$"
AFTER="/tmp/dot-doctor.after.$$"

trap 'rm -f "$BEFORE" "$AFTER"' EXIT

# Step 1: capture pre-apply doctor state (doctor exits 1/2 on drift — suppress with || true)
log_section "dot apply"
log_info "Capturing pre-apply health state…"
bash "$REPO_ROOT/scripts/doctor.sh" --no-color > "$BEFORE" 2>&1 || true

# Step 2: chezmoi apply (AC B5: bail with message on failure, no delta printed)
log_info "Running chezmoi apply…"
if ! chezmoi apply; then
    log_error "chezmoi apply failed — no changes applied."
    exit 1
fi

# Step 3: capture post-apply doctor state; preserve exit code
log_info "Capturing post-apply health state…"
doctor_rc=0
bash "$REPO_ROOT/scripts/doctor.sh" --no-color > "$AFTER" 2>&1 || doctor_rc=$?

# ── Delta section ──
# doctor output lines look like (--no-color):
#   [OK]    <label>           <details>
#   [WARN]  <label>           <details>
#   [FAIL]  <label>           <details>
#
# Strategy: for every label that appears in both snapshots, compare status.
# Print transitions and current state.

log_section "Health delta"

# Extract status and label from a doctor snapshot file.
# Output: "<STATUS> <label>" — one line per status line, status is OK/WARN/FAIL.
extract_status_labels() {
    local file="$1"
    # Match lines starting with [OK], [WARN], or [FAIL].
    # Output: "<STATUS> <first-token-of-label>" — one line per status line.
    grep -E '^\[(OK|WARN|FAIL)\]' "$file" \
        | sed -E 's/^\[([A-Z]+)\][[:space:]]+([^[:space:]]+).*/\1 \2/' \
        || true
}

# Build parallel indexed arrays: label -> status (before and after).
# bash 3.2 compat — no declare -A.
BEFORE_LABELS=()  BEFORE_STATUSES=()
AFTER_LABELS=()   AFTER_STATUSES=()

while IFS= read -r line; do
    BEFORE_STATUSES+=("${line%% *}")
    BEFORE_LABELS+=("${line#* }")
done < <(extract_status_labels "$BEFORE")

while IFS= read -r line; do
    AFTER_STATUSES+=("${line%% *}")
    AFTER_LABELS+=("${line#* }")
done < <(extract_status_labels "$AFTER")

# Lookup helpers — iterate own arrays directly (no eval).
lookup_before() {
    local target="$1" i
    for i in "${!BEFORE_LABELS[@]}"; do
        if [[ "${BEFORE_LABELS[$i]}" == "$target" ]]; then
            printf "%s" "${BEFORE_STATUSES[$i]}"
            return
        fi
    done
    printf "UNKNOWN"
}

lookup_after() {
    local target="$1" i
    for i in "${!AFTER_LABELS[@]}"; do
        if [[ "${AFTER_LABELS[$i]}" == "$target" ]]; then
            printf "%s" "${AFTER_STATUSES[$i]}"
            return
        fi
    done
    printf "UNKNOWN"
}

# Determine color support (stdout is likely a tty; log.sh already set COLOR_* if sourced)
if [[ -t 1 ]]; then
    _GREEN=$'\033[32m'
    _YELLOW=$'\033[33m'
    _RED=$'\033[31m'
    _RESET=$'\033[0m'
else
    _GREEN="" _YELLOW="" _RED="" _RESET=""
fi

fixed=0
remaining_warn=0
remaining_fail=0
any_change=0

# Collect all labels from after-state (primary view post-apply).
# AFTER_LABELS is already populated above — reuse it directly.
ALL_LABELS=("${AFTER_LABELS[@]+"${AFTER_LABELS[@]}"}")

printed_labels=()

for label in "${ALL_LABELS[@]}"; do
    # Deduplicate (associative arrays coalesce, but loop may re-visit)
    already=0
    for pl in "${printed_labels[@]+"${printed_labels[@]}"}"; do
        [[ "$pl" == "$label" ]] && { already=1; break; }
    done
    [[ "$already" -eq 1 ]] && continue
    printed_labels+=("$label")

    before="$(lookup_before "$label")"
    after="$(lookup_after "$label")"

    if [[ "$before" != "$after" ]]; then
        any_change=1
        if [[ "$after" == "OK" ]]; then
            printf "  %s✓ fixed%s   %-24s  %s → %s\n" \
                "$_GREEN" "$_RESET" "$label" "$before" "$after"
            (( fixed++ )) || true
        elif [[ "$after" == "WARN" ]]; then
            printf "  %s! changed%s %-24s  %s → %s\n" \
                "$_YELLOW" "$_RESET" "$label" "$before" "$after"
            (( remaining_warn++ )) || true
        elif [[ "$after" == "FAIL" ]]; then
            printf "  %s✗ changed%s %-24s  %s → %s\n" \
                "$_RED" "$_RESET" "$label" "$before" "$after"
            (( remaining_fail++ )) || true
        fi
    else
        # No transition — still report WARN/FAIL persisting
        if [[ "$after" == "WARN" ]]; then
            printf "  %s! warn%s    %-24s  still WARN\n" \
                "$_YELLOW" "$_RESET" "$label"
            (( remaining_warn++ )) || true
        elif [[ "$after" == "FAIL" ]]; then
            printf "  %s✗ fail%s    %-24s  still FAIL\n" \
                "$_RED" "$_RESET" "$label"
            (( remaining_fail++ )) || true
        fi
    fi
done

printf "\n"
if [[ "$fixed" -gt 0 || "$any_change" -gt 0 ]]; then
    printf "  Summary: %d fixed, %d warn, %d fail\n" "$fixed" "$remaining_warn" "$remaining_fail"
elif [[ "$remaining_warn" -eq 0 && "$remaining_fail" -eq 0 ]]; then
    log_ok "All checks passed — no issues found."
else
    printf "  Summary: %d warn, %d fail (no change from apply)\n" "$remaining_warn" "$remaining_fail"
fi

exit "$doctor_rc"
