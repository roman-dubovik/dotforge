#!/usr/bin/env bash
# dot pull — fetch + fast-forward pull the chezmoi source repo, apply, then run doctor.
#
# Usage:
#   scripts/dot-pull.sh           # fetch, pull (ff-only), chezmoi apply, dot doctor
#   scripts/dot-pull.sh --help|-h # print this help

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

# ── Argument parsing ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
dot pull — sync chezmoi source repo and apply dotfiles

Usage:
  dot pull              Fetch origin, pull --ff-only, chezmoi apply, then run
                        dot doctor. Exit code matches doctor's exit code.
  dot pull --help|-h    Print this help.

Environment:
  DOTFORGE_BRANCH       Remote branch to pull (default: main).

Steps:
  1. chezmoi git -- fetch origin <branch>
  2. chezmoi git -- pull --ff-only origin <branch>
     (If already up-to-date this is a no-op. Non-fast-forward → bail.)
  3. chezmoi apply
  4. dot doctor (exit code propagated)

Notes:
  - Only 'origin' remote is supported.
  - No interactive prompts — all feedback via exit codes and log messages.
  - Ensure SSH keys or git credentials are configured; HTTPS+token may hang.
EOF
            exit 0
            ;;
        *)
            printf "dot pull: unknown argument: %s\n" "$1" >&2
            printf "Run 'dot pull --help' for usage.\n" >&2
            exit 2
            ;;
    esac
done

# ── Configuration ──

BRANCH="${DOTFORGE_BRANCH:-main}"

# ── Pull flow ──

log_section "dot pull"

# Step 1: fetch
log_info "Fetching origin/$BRANCH…"
if ! chezmoi git -- fetch origin "$BRANCH"; then
    log_error "[dot pull] fetch failed"
    exit 1
fi

# Step 2: pull --ff-only (up-to-date is a no-op; non-ff git prints error + exits non-zero)
log_info "Pulling --ff-only…"
if ! chezmoi git -- pull --ff-only origin "$BRANCH"; then
    log_error "[dot pull] pull failed (likely non-fast-forward — resolve manually)"
    exit 1
fi

# Step 3: apply chezmoi state
log_info "Applying chezmoi state…"
if ! chezmoi apply; then
    log_error "[dot pull] apply failed"
    exit 1
fi

# Step 4: final health check (exec replaces process; exit code = doctor's exit code)
log_section "Final health check"
exec bash "$REPO_ROOT/scripts/doctor.sh"
