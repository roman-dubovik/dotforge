#!/usr/bin/env bash
# dot pull — fetch + pull the chezmoi source repo, apply, then run doctor.
#
# Usage:
#   scripts/dot-pull.sh                       # fetch, pull (ff-only), chezmoi apply, dot doctor
#   scripts/dot-pull.sh --resolve=abort       # same as above (default)
#   scripts/dot-pull.sh --resolve=ours        # stash → pull → on conflict keep ours → stash pop
#   scripts/dot-pull.sh --resolve=theirs      # stash → pull → on conflict keep theirs → stash pop
#   scripts/dot-pull.sh --resolve=interactive # stash → pull → on conflict ask per-file → stash pop
#   scripts/dot-pull.sh --help|-h             # print this help

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

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/git-state.sh"

# ── Argument parsing ──

RESOLVE_MODE="abort"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resolve=abort|--resolve=ours|--resolve=theirs|--resolve=interactive)
            RESOLVE_MODE="${1#--resolve=}"
            shift
            ;;
        --resolve=*)
            printf "dot pull: unknown --resolve mode '%s'\n" "${1#--resolve=}" >&2
            printf "Valid modes: abort, ours, theirs, interactive\n" >&2
            exit 2
            ;;
        --help|-h)
            cat <<'EOF'
dot pull — sync chezmoi source repo and apply dotfiles

Usage:
  dot pull [--resolve=MODE]    Fetch origin, pull, chezmoi apply, then run
                               dot doctor. Exit code matches doctor's exit code.
  dot pull --help|-h           Print this help.

Resolve modes (default: abort):
  abort         Fast-forward only pull; bail immediately on non-fast-forward.
                This is the default and is identical to previous behaviour.
  ours          Stash local changes → pull → on conflict keep local version of
                each conflicted file → commit → stash pop.
  theirs        Stash local changes → pull → on conflict take remote version of
                each conflicted file → commit → stash pop.
  interactive   Stash → pull → on conflict prompt per file (gum or read -p).

Environment:
  DOTFORGE_BRANCH       Remote branch to pull (default: main).

Steps (abort mode):
  1. chezmoi git -- fetch origin <branch>
  2. chezmoi git -- pull --ff-only origin <branch>
     (If already up-to-date this is a no-op. Non-fast-forward → bail.)
  3. chezmoi apply
  4. dot doctor (exit code propagated)

Steps (ours/theirs/interactive modes):
  1. chezmoi git -- fetch origin <branch>
  2. git stash (if working tree dirty)
  3. chezmoi git -- pull origin <branch>  (merge, not ff-only)
  4. On conflict: resolve per mode
  5. chezmoi apply
  6. git stash pop (if stashed)
  7. dot doctor

Notes:
  - Only 'origin' remote is supported.
  - On any error in ours/theirs/interactive: stash is restored with message.
  - Ensure SSH keys or git credentials are configured.
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

# The chezmoi source repo directory for git operations.
# In tests, override via DOTFORGE_CHEZMOI_REPO.
CHEZMOI_REPO="${DOTFORGE_CHEZMOI_REPO:-$(chezmoi source-path 2>/dev/null || printf "%s/.local/share/chezmoi" "$HOME")}"

# Path to doctor script; override DOTFORGE_DOCTOR_SCRIPT to inject a stub in CI/tests.
DOCTOR_SCRIPT="${DOTFORGE_DOCTOR_SCRIPT:-$REPO_ROOT/scripts/doctor.sh}"

# ── abort mode (default) — byte-for-byte identical to original behaviour ──

if [[ "$RESOLVE_MODE" == "abort" ]]; then
    log_section "dot pull"

    # Step 1: fetch
    log_info "Fetching origin/${BRANCH}…"
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
    exec bash "$DOCTOR_SCRIPT"
fi

# ── ours / theirs / interactive modes ──

log_section "dot pull --resolve=${RESOLVE_MODE}"

# Helper: resolve conflicts using the chosen strategy.
# Iterates all conflicted files and applies git_resolve_file for ours/theirs,
# or prompts per-file for interactive mode.
_resolve_conflicts() {
    local mode="$1"
    local repo="$2"
    local conflicted_file f choice

    conflicted_file="$(git_conflicted_files "$repo")"
    if [[ -z "$conflicted_file" ]]; then
        return 0
    fi

    # Save original stdin to fd 3 so interactive prompts can read it even
    # when the while loop redirects stdin via a here-doc.
    exec 3<&0

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$mode" in
            ours|theirs)
                log_info "Resolving conflict in $f (--${mode})…"
                if ! git_resolve_file "$repo" "$f" "$mode"; then
                    log_error "Failed to resolve $f via --${mode}"
                    return 1
                fi
                log_ok "Resolved: $f (kept ${mode})"
                ;;
            interactive)
                # Ask user per-file: keep local (ours) or take remote (theirs).
                # Use gum only when stdin is a tty (gum requires interactive input).
                choice=""
                if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
                    if gum confirm "Conflict in '$f' — keep local version? (no = take remote)"; then
                        choice="ours"
                    else
                        choice="theirs"
                    fi
                else
                    printf "Conflict in '%s' — keep local? [y/n]: " "$f"
                    # Read from fd 3 (redirected from stdin before the while loop)
                    # or fall back to /dev/tty if available.
                    _ans=""
                    if read -r _ans <&3 2>/dev/null; then
                        :
                    elif [[ -c /dev/tty ]]; then
                        read -r _ans </dev/tty
                    fi
                    case "$_ans" in
                        y|Y|yes|YES) choice="ours"   ;;
                        *)           choice="theirs" ;;
                    esac
                fi
                log_info "Resolving $f (${choice})…"
                if ! git_resolve_file "$repo" "$f" "$choice"; then
                    log_error "Failed to resolve $f"
                    return 1
                fi
                log_ok "Resolved: $f (${choice})"
                ;;
        esac
    done <<EOF
$conflicted_file
EOF
    exec 3<&-
}

# Step 1: fetch
log_info "Fetching origin/${BRANCH}…"
if ! chezmoi git -- fetch origin "$BRANCH"; then
    log_error "[dot pull] fetch failed"
    exit 1
fi

# Step 2: stash working tree if dirty
STASH_REF=""
STASH_SAVED=0
if git_is_dirty "$CHEZMOI_REPO"; then
    log_info "Stashing local changes…"
    STASH_REF="$(git_stash_save "$CHEZMOI_REPO" "dot-pull auto-stash $(date +%Y-%m-%dT%H:%M:%S)")" || true
    if [[ -n "$STASH_REF" ]]; then
        STASH_SAVED=1
        log_ok "Stashed as ${STASH_REF}"
    fi
fi

# Cleanup helper: restore stash on any early exit.
_restore_stash() {
    if [[ "$STASH_SAVED" -eq 1 ]]; then
        log_warn "Restoring stash ${STASH_REF}…"
        # If a merge is in progress, stash pop refuses to run.  Abort it first.
        if [[ -e "$CHEZMOI_REPO/.git/MERGE_HEAD" ]]; then
            log_warn "Active merge detected — aborting merge before stash pop…"
            chezmoi git -- merge --abort >/dev/null 2>&1 || true
        fi
        if git -C "$CHEZMOI_REPO" stash pop "$STASH_REF" >/dev/null 2>&1; then
            log_warn "stash restored"
        else
            log_error "stash pop failed — stash NOT restored — listed in 'git stash list', resolve manually: run 'git stash list' in chezmoi source"
        fi
    fi
}

# Step 3: merge origin/<branch> (no-ff to allow merge commit even if ff is possible)
# This avoids the git "diverging branches, can't fast-forward" abort on modern git.
log_info "Pulling origin/${BRANCH}…"
PULL_RC=0
chezmoi git -- pull --no-ff origin "$BRANCH" >/dev/null 2>&1 || PULL_RC=$?

if [[ "$PULL_RC" -ne 0 ]]; then
    # Check if there are actual conflicts to resolve
    if [[ -n "$(git_conflicted_files "$CHEZMOI_REPO")" ]]; then
        log_info "Conflicts detected — resolving with mode: ${RESOLVE_MODE}…"

        if ! _resolve_conflicts "$RESOLVE_MODE" "$CHEZMOI_REPO"; then
            log_error "Conflict resolution failed"
            _restore_stash
            exit 1
        fi

        # Commit the resolution
        if ! git_commit_no_edit "$CHEZMOI_REPO"; then
            log_error "Failed to commit resolved merge"
            _restore_stash
            exit 1
        fi
        log_ok "Merge committed."
    else
        log_error "[dot pull] pull failed (non-fast-forward or network error)"
        _restore_stash
        exit 1
    fi
fi

# Step 4: apply chezmoi state
log_info "Applying chezmoi state…"
if ! chezmoi apply; then
    log_error "[dot pull] apply failed"
    _restore_stash
    exit 1
fi

# Step 5: pop stash
if [[ "$STASH_SAVED" -eq 1 ]]; then
    log_info "Restoring local changes (stash pop)…"
    if ! git_stash_pop "$CHEZMOI_REPO" "$STASH_REF"; then
        # Conflict on pop: use same side as pull-conflict resolution.
        # In stash-pop context "ours" = HEAD (already merged) = correct for ours mode.
        # For interactive mode, fall back to "ours" (preserve merged state).
        local_pop_mode="ours"

        log_warn "Stash pop had conflicts — auto-resolving pop conflicts with ${local_pop_mode}…"
        _stash_conflicts="$(git_conflicted_files "$CHEZMOI_REPO")"

        while IFS= read -r _f; do
            [[ -z "$_f" ]] && continue
            if ! git_resolve_file "$CHEZMOI_REPO" "$_f" "$local_pop_mode"; then
                log_error "Failed to resolve stash-pop conflict in $_f"
                log_warn "stash restored, resolve manually"
                exit 1
            fi
            log_ok "Stash-pop conflict resolved: $_f (${local_pop_mode})"
        done <<EOF
$_stash_conflicts
EOF

        log_ok "Stash-pop conflicts resolved."
    else
        log_ok "Local changes restored."
    fi
fi

# Step 6: final health check
log_section "Final health check"
exec bash "$DOCTOR_SCRIPT"
