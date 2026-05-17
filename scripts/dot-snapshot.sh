#!/usr/bin/env bash
# dot snapshot — capture machine state to canonical files and offer a git commit.
#
# Usage:
#   scripts/dot-snapshot.sh                  # scan CLI globals + login items + macOS defaults, confirm, commit
#   scripts/dot-snapshot.sh --no-cli         # skip CLI globals scan
#   scripts/dot-snapshot.sh --no-autostart   # skip login items scan
#   scripts/dot-snapshot.sh --no-macos       # skip macOS defaults scan
#   scripts/dot-snapshot.sh --help|-h        # print this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh" 2>/dev/null || {
    # fallback no-op loggers if lib/log.sh missing
    log_info()    { printf "%s\n" "$*"; }
    log_ok()      { printf "✓ %s\n" "$*"; }
    log_warn()    { printf "WARN: %s\n" "$*" >&2; }
    log_error()   { printf "ERROR: %s\n" "$*" >&2; }
    log_step()    { local c="$1" t="$2"; shift 2; printf "[%s/%s] %s\n" "$c" "$t" "$*"; }
    log_section() { printf "\n── %s ──\n" "$*"; }
}

# ── gum helpers (C7) ────────────────────────────────────────────────────────

gum_confirm() {
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$@"
    else
        # $1 is the prompt text; extra args are ignored in fallback
        local a
        read -r -p "$1 [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]]
    fi
}

gum_input() {
    if command -v gum >/dev/null 2>&1; then
        gum input "$@"
        return
    fi
    # Parse --value and --prompt from args; ignore other gum-specific flags
    local val="" prompt="> "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --value)  val="$2";   shift 2 ;;
            --prompt) prompt="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done
    local answer
    # read returns non-zero on EOF/Ctrl-D — propagate as cancel signal
    if ! read -r -p "$prompt" answer; then
        return 1
    fi
    printf "%s" "${answer:-$val}"
}

# ── Argument parsing ─────────────────────────────────────────────────────────

RUN_CLI=1
RUN_AUTOSTART=1
RUN_MACOS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
dot snapshot — capture machine state to canonical files and offer a git commit

Usage:
  dot snapshot               Scan CLI globals + login items + macOS defaults, confirm per-file, commit.
  dot snapshot --no-cli      Skip CLI globals scan (scan-cli --capture).
  dot snapshot --no-autostart  Skip login items scan (scan-login-autostart --capture).
  dot snapshot --no-macos    Skip macOS defaults scan (scan-macos-defaults --capture).
  dot snapshot --help|-h     Print this help.

Notes:
  - Requires a clean git index (no pre-staged changes).
  - Uses 'gum' for interactive prompts if available; falls back to plain read.
  - Does NOT push after committing.
EOF
            exit 0
            ;;
        --no-cli)
            RUN_CLI=0
            shift
            ;;
        --no-autostart)
            RUN_AUTOSTART=0
            shift
            ;;
        --no-macos)
            RUN_MACOS=0
            shift
            ;;
        *)
            log_error "dot snapshot: unknown argument: $1"
            printf "Run 'dot snapshot --help' for usage.\n" >&2
            exit 2
            ;;
    esac
done

# ── C2: nothing-to-snapshot guard ───────────────────────────────────────────

if [[ $RUN_CLI -eq 0 && $RUN_AUTOSTART -eq 0 && $RUN_MACOS -eq 0 ]]; then
    log_error "nothing to snapshot (all scanners disabled: --no-cli, --no-autostart, --no-macos)"
    exit 2
fi

# ── C0: staged-changes precondition guard ────────────────────────────────────

staged="$(git -C "$REPO_ROOT" diff --cached --name-only)"
if [[ -n "$staged" ]]; then
    log_error "[dot snapshot] repo has staged changes, commit or stash them first"
    exit 1
fi

# ── Compute total steps for progress display ─────────────────────────────────

TOTAL_STEPS=$(( RUN_CLI + RUN_AUTOSTART + RUN_MACOS ))
CURRENT_STEP=0

# ── C1: run sub-scanners ─────────────────────────────────────────────────────

CAPTURED_FILES=()

if [[ $RUN_CLI -eq 1 ]]; then
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    log_step "$CURRENT_STEP" "$TOTAL_STEPS" "scanning CLI globals..."
    bash "$REPO_ROOT/scripts/scan-cli.sh" --capture
    CAPTURED_FILES+=("cli-globals.txt")
fi

if [[ $RUN_AUTOSTART -eq 1 ]]; then
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    log_step "$CURRENT_STEP" "$TOTAL_STEPS" "scanning login items..."
    bash "$REPO_ROOT/scripts/scan-login-autostart.sh" --capture
    CAPTURED_FILES+=("login-items.txt")
fi

if [[ $RUN_MACOS -eq 1 ]]; then
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    log_step "$CURRENT_STEP" "$TOTAL_STEPS" "scanning macOS defaults..."
    bash "$REPO_ROOT/scripts/scan-macos-defaults.sh" --capture
    CAPTURED_FILES+=("chezmoi/dot_config/dotforge/macos-defaults.txt")
fi

# ── C3: check for changes ─────────────────────────────────────────────────────

log_section "Checking for changes"

status_out="$(git -C "$REPO_ROOT" status --short -- "${CAPTURED_FILES[@]}")"
if [[ -z "$status_out" ]]; then
    log_ok "No changes captured."
    exit 0
fi

# ── C4: per-file confirm and git add ─────────────────────────────────────────

log_section "Review and stage changes"

for f in "${CAPTURED_FILES[@]}"; do
    file_path="$REPO_ROOT/$f"

    # Check if this specific file changed (tracked or untracked)
    file_status="$(git -C "$REPO_ROOT" status --short -- "$f")"
    [[ -z "$file_status" ]] && continue

    printf "\n"
    log_info "Changes in: %s" "$f"

    # Show diff — handle untracked (new) files gracefully
    if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        git -C "$REPO_ROOT" diff --color=always -- "$f" | head -n 30
    else
        printf "(new file — not yet tracked)\n"
        head -n 30 "$file_path" 2>/dev/null || true
    fi

    printf "\n"
    if gum_confirm "Commit changes to $f?"; then
        if ! git -C "$REPO_ROOT" add -- "$f"; then
            log_error "[dot snapshot] git add failed for $f"
            exit 1
        fi
        log_ok "Staged: $f"
    else
        log_warn "Skipped: $f"
    fi
done

# ── C5/C6: commit if anything staged ─────────────────────────────────────────

staged_after="$(git -C "$REPO_ROOT" diff --cached --name-only)"
if [[ -z "$staged_after" ]]; then
    log_warn "No files staged. Aborting commit."
    exit 0
fi

log_section "Commit snapshot"

default_msg="snapshot: $(hostname -s) $(date +%F)"
if ! MSG="$(gum_input --value "$default_msg" --prompt "Commit message: ")"; then
    log_warn "Commit message input cancelled. Aborting commit."
    exit 0
fi
if [[ -z "$MSG" ]]; then
    MSG="$default_msg"
fi

git -C "$REPO_ROOT" commit -m "$MSG"
log_ok "Committed: $MSG"
