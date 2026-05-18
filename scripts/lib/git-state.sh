#!/usr/bin/env bash
# scripts/lib/git-state.sh — git divergence and stash helpers for dot-pull / dot-status.
#
# Public API:
#   git_ahead_count   GIT_DIR  REMOTE_REF   # number of local commits not in remote
#   git_behind_count  GIT_DIR  REMOTE_REF   # number of remote commits not in local
#   git_is_dirty      GIT_DIR               # 0 if working tree has uncommitted changes, 1 if clean
#   git_stash_save    GIT_DIR  MSG          # stash; prints stash ref on stdout; exit 1 if nothing to stash
#   git_stash_pop     GIT_DIR  STASH_REF    # pop a specific stash ref; exit 1 on conflict
#   git_conflicted_files GIT_DIR            # print list of conflicted files (one per line)
#   git_resolve_file  GIT_DIR  FILE  SIDE   # checkout --ours or --theirs for one file, then git add
#   git_commit_no_edit GIT_DIR             # git commit --no-edit (finish merge/stash-pop commit)
#
# All functions take GIT_DIR as first arg so tests can pass a temp repo path.
# Bash 3.2 compatible: no declare -A, no mapfile, no process-substitution arrays.

# ── git_ahead_count ──
# Prints number of commits that are on HEAD but not on REMOTE_REF.
# Prints 0 if REMOTE_REF does not exist (offline / never fetched).
git_ahead_count() {
    local git_dir="$1"
    local remote_ref="$2"
    # Verify remote ref exists; if not, print 0 (offline-safe).
    if ! git -C "$git_dir" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        printf "0"
        return 0
    fi
    git -C "$git_dir" rev-list --count "${remote_ref}..HEAD" 2>/dev/null || printf "0"
}

# ── git_behind_count ──
# Prints number of commits on REMOTE_REF not yet on HEAD.
# Prints 0 if REMOTE_REF does not exist.
git_behind_count() {
    local git_dir="$1"
    local remote_ref="$2"
    if ! git -C "$git_dir" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        printf "0"
        return 0
    fi
    git -C "$git_dir" rev-list --count "HEAD..${remote_ref}" 2>/dev/null || printf "0"
}

# ── git_is_dirty ──
# Returns 0 (true) if the working tree has uncommitted changes; 1 (false) if clean.
git_is_dirty() {
    local git_dir="$1"
    # --porcelain: empty output = clean
    local status_output
    status_output="$(git -C "$git_dir" status --porcelain 2>/dev/null)"
    [[ -n "$status_output" ]]
}

# ── git_stash_save ──
# Saves the current working tree + index (including untracked files, -u) to a
# new stash with MSG.  Using -u ensures git_is_dirty and git_stash_save agree on
# what constitutes a "dirty" working tree (untracked files are included in both).
# Prints the stash reference (e.g. "stash@{0}") on stdout.
# Returns 1 if there is nothing to stash (clean working tree).
git_stash_save() {
    local git_dir="$1"
    local msg="$2"
    local output
    output="$(git -C "$git_dir" stash push -u -m "$msg" 2>&1)"
    local rc=$?
    if [[ "$output" == *"No local changes to save"* ]]; then
        return 1
    fi
    if [[ $rc -ne 0 ]]; then
        printf "%s\n" "$output" >&2
        return 1
    fi
    # Find the stash ref that matches the message; stash@{0} is always the most recent.
    printf "stash@{0}"
}

# ── git_stash_pop ──
# Pops a specific stash ref.
# Returns 0 on clean pop; 1 on conflict (leaves MERGE_HEAD / conflict markers in place).
git_stash_pop() {
    local git_dir="$1"
    local stash_ref="$2"
    git -C "$git_dir" stash pop "$stash_ref" >/dev/null 2>&1
}

# ── git_conflicted_files ──
# Prints paths of files with unresolved merge conflicts (one per line).
# Output is empty if no conflicts.
git_conflicted_files() {
    local git_dir="$1"
    git -C "$git_dir" diff --name-only --diff-filter=U 2>/dev/null
}

# ── git_resolve_file ──
# Resolves a conflict in FILE by checking out SIDE (ours or theirs) and staging it.
# SIDE: "ours" | "theirs"
git_resolve_file() {
    local git_dir="$1"
    local file="$2"
    local side="$3"
    git -C "$git_dir" checkout "--${side}" -- "$file" && \
    git -C "$git_dir" add -- "$file"
}

# ── git_commit_no_edit ──
# Runs git commit --no-edit inside GIT_DIR (finishes a merge commit).
git_commit_no_edit() {
    local git_dir="$1"
    git -C "$git_dir" commit --no-edit
}
