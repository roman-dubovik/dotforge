#!/usr/bin/env bash
# dot status — non-destructive divergence report for the chezmoi source repo.
#
# Usage:
#   scripts/dot-status.sh           # report divergence using already-fetched remote refs
#   scripts/dot-status.sh --fetch   # fetch origin first, then report
#   scripts/dot-status.sh --help|-h # print this help
#
# Exit codes:
#   0 — everything in-sync (no divergence detected)
#   1 — one or more divergences detected
#   2 — usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh" 2>/dev/null || {
    log_info()    { printf "→ %s\n" "$*"; }
    log_warn()    { printf "! %s\n" "$*" >&2; }
    log_section() { printf "\n── %s ──\n" "$*"; }
}

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/git-state.sh"

# ── Argument parsing ──

DO_FETCH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fetch)
            DO_FETCH=1
            shift
            ;;
        --help|-h)
            cat <<'EOF'
dot status — non-destructive divergence report

Usage:
  dot status            Report ahead/behind, working tree, scanner outputs,
                        and dot doctor summary.  Does NOT fetch.
  dot status --fetch    Fetch origin before computing divergence (opt-in).
  dot status --help|-h  Print this help.

Output sections:
  remote          origin/<branch> used as reference
  ahead/behind    local commits not on remote / remote commits not local
  working tree    clean or dirty (uncommitted changes present)
  scanner outputs uncommitted scanner capture files (cli-globals, login-items,
                  macos-defaults) present in working tree but not yet committed
  dot doctor      PASS/WARN/FAIL count from a read-only doctor run

Exit codes:
  0  everything in-sync
  1  one or more divergences detected
  2  usage error

Notes:
  - dot status never modifies the repo, stash, or chezmoi state.
  - Use 'dot status --fetch' to get an up-to-date behind count.
  - Use 'dot pull' to actually sync.
EOF
            exit 0
            ;;
        *)
            printf "dot status: unknown argument: %s\n" "$1" >&2
            printf "Run 'dot status --help' for usage.\n" >&2
            exit 2
            ;;
    esac
done

# ── Configuration ──

BRANCH="${DOTFORGE_BRANCH:-main}"
REMOTE_REF="origin/${BRANCH}"

# The chezmoi source repo directory (used for all git operations).
# In tests, override via DOTFORGE_CHEZMOI_REPO.
CHEZMOI_REPO="${DOTFORGE_CHEZMOI_REPO:-$(chezmoi source-path 2>/dev/null || printf "%s/.local/share/chezmoi" "$HOME")}"

# Path to doctor script; override DOTFORGE_DOCTOR_SCRIPT to inject a stub in CI/tests.
DOCTOR_SCRIPT="${DOTFORGE_DOCTOR_SCRIPT:-$REPO_ROOT/scripts/doctor.sh}"

# Scanner output files (relative to REPO_ROOT, not CHEZMOI_REPO).
# Override for tests via DOTFORGE_SCANNER_FILES (colon-separated list).
_DEFAULT_SCANNER_FILES="${REPO_ROOT}/cli-globals.txt:${REPO_ROOT}/login-items.txt:${REPO_ROOT}/chezmoi/dot_config/dotforge/macos-defaults.txt"
SCANNER_FILES="${DOTFORGE_SCANNER_FILES:-$_DEFAULT_SCANNER_FILES}"

DIVERGED=0

# ── Optional fetch ──

if [[ "$DO_FETCH" -eq 1 ]]; then
    log_info "Fetching origin/${BRANCH}…"
    fetch_err=""
    if ! fetch_err="$(chezmoi git -- fetch origin "$BRANCH" 2>&1)"; then
        log_warn "fetch failed — divergence counts may be stale: ${fetch_err}"
        DIVERGED=1
    fi
fi

# ── Gather divergence data ──

log_section "dot status"

# (a) ahead / behind
ahead="$(git_ahead_count  "$CHEZMOI_REPO" "$REMOTE_REF")"
behind="$(git_behind_count "$CHEZMOI_REPO" "$REMOTE_REF")"

# Check if remote ref actually exists
remote_known=1
if ! git -C "$CHEZMOI_REPO" rev-parse --verify "$REMOTE_REF" >/dev/null 2>&1; then
    remote_known=0
fi

printf "  remote:            %s\n" "$REMOTE_REF"

if [[ "$remote_known" -eq 0 ]]; then
    printf "  ahead/behind:      unknown (remote ref not found — try --fetch)\n"
else
    printf "  commits ahead:     %s\n" "$ahead"
    printf "  commits behind:    %s\n" "$behind"
    [[ "$ahead" -ne 0 || "$behind" -ne 0 ]] && DIVERGED=1
fi

# (b) working tree
if git_is_dirty "$CHEZMOI_REPO"; then
    printf "  working tree:      dirty (uncommitted changes present)\n"
    DIVERGED=1
else
    printf "  working tree:      clean\n"
fi

# (c) uncommitted scanner outputs
# These files live in the *dotforge repo* (REPO_ROOT), not in CHEZMOI_REPO.
# We check if any of the known scanner output files have uncommitted changes
# in the dotforge repo itself.
_dirty_scanners=()
_old_ifs="$IFS"
IFS=":"
for sf in $SCANNER_FILES; do
    IFS="$_old_ifs"
    [[ -z "$sf" ]] && continue
    if [[ -f "$sf" ]]; then
        # Check if this file is modified relative to HEAD in the dotforge repo
        rel="${sf#"${REPO_ROOT}"/}"
        if git -C "$REPO_ROOT" status --porcelain -- "$rel" 2>/dev/null | grep -q .; then
            _dirty_scanners+=("$rel")
        fi
    fi
done
IFS="$_old_ifs"

if [[ "${#_dirty_scanners[@]}" -gt 0 ]]; then
    printf "  scanner outputs:   %d uncommitted capture file(s):\n" "${#_dirty_scanners[@]}"
    for _ds in "${_dirty_scanners[@]}"; do
        printf "    %s\n" "$_ds"
    done
    DIVERGED=1
else
    printf "  scanner outputs:   none uncommitted\n"
fi

# (d) dot doctor summary (read-only)
printf "  dot doctor:        "
_doctor_out="/tmp/dot-status-doctor.$$"

_doctor_rc=0
bash "$DOCTOR_SCRIPT" --no-color > "$_doctor_out" 2>&1 || _doctor_rc=$?
_pass="$(awk '/^\[OK\]/'   "$_doctor_out" 2>/dev/null | awk 'END{print NR}')"
_warn="$(awk '/^\[WARN\]/' "$_doctor_out" 2>/dev/null | awk 'END{print NR}')"
_fail="$(awk '/^\[FAIL\]/' "$_doctor_out" 2>/dev/null | awk 'END{print NR}')"
rm -f "$_doctor_out"

# Doctor exited non-zero but emitted no FAIL/WARN → crash mid-run (possibly after partial [OK] output).
# Check this BEFORE the normal warn/fail branches so the normal paths still apply
# when doctor exits non-zero and does emit [WARN]/[FAIL] lines.
if [[ "$_doctor_rc" -ne 0 ]] && [[ "$_warn" -eq 0 ]] && [[ "$_fail" -eq 0 ]]; then
    printf "ERROR (doctor exited %s with %s pass, no warn/fail output — likely crash)\n" "$_doctor_rc" "$_pass"
    DIVERGED=1
elif [[ "$_fail" -gt 0 ]]; then
    printf "FAIL (%s pass, %s warn, %s fail)\n" "$_pass" "$_warn" "$_fail"
    DIVERGED=1
elif [[ "$_warn" -gt 0 ]]; then
    printf "WARN (%s pass, %s warn, %s fail)\n" "$_pass" "$_warn" "$_fail"
    DIVERGED=1
else
    printf "PASS (%s pass, %s warn, %s fail)\n" "$_pass" "$_warn" "$_fail"
fi

printf "\n"

exit "$DIVERGED"
