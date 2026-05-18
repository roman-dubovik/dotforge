#!/usr/bin/env bats
# Unit tests for scripts/lib/git-state.sh helpers.
# Creates a fresh git repo fixture in BATS_TEST_TMPDIR per test.
# chezmoi is NOT involved — helpers use plain `git -C <dir>`.

setup() {
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/git-state.sh"

    # Create a local "remote" bare repo and a local "working" clone.
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    WORK_DIR="$BATS_TEST_TMPDIR/work"

    git init --bare "$REMOTE_DIR" >/dev/null 2>&1
    git clone "$REMOTE_DIR" "$WORK_DIR" >/dev/null 2>&1

    # Configure identity for commits.
    git -C "$WORK_DIR" config user.email "test@test.local"
    git -C "$WORK_DIR" config user.name  "Test"

    # Initial commit (needed so HEAD and origin/main exist).
    printf "init\n" > "$WORK_DIR/file.txt"
    git -C "$WORK_DIR" add file.txt
    git -C "$WORK_DIR" commit -m "init" >/dev/null 2>&1
    git -C "$WORK_DIR" push origin HEAD:main >/dev/null 2>&1
    git -C "$WORK_DIR" checkout -b main >/dev/null 2>&1 || true
    # Ensure remote-tracking ref is set up
    git -C "$WORK_DIR" fetch origin >/dev/null 2>&1
    git -C "$WORK_DIR" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
}

# ── git_ahead_count ──

@test "git_ahead_count: 0 when up-to-date" {
    run git_ahead_count "$WORK_DIR" "origin/main"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "git_ahead_count: 1 after local commit" {
    printf "local\n" >> "$WORK_DIR/file.txt"
    git -C "$WORK_DIR" add file.txt
    git -C "$WORK_DIR" commit -m "local commit" >/dev/null 2>&1

    run git_ahead_count "$WORK_DIR" "origin/main"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "git_ahead_count: 0 when remote ref absent (offline-safe)" {
    run git_ahead_count "$WORK_DIR" "origin/nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ── git_behind_count ──

@test "git_behind_count: 0 when up-to-date" {
    run git_behind_count "$WORK_DIR" "origin/main"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "git_behind_count: 1 after remote commit" {
    # Simulate remote advance: push a commit from a second clone.
    WORK2="$BATS_TEST_TMPDIR/work2"
    git clone "$REMOTE_DIR" "$WORK2" >/dev/null 2>&1
    git -C "$WORK2" config user.email "test@test.local"
    git -C "$WORK2" config user.name  "Test"
    printf "remote\n" >> "$WORK2/file.txt"
    git -C "$WORK2" add file.txt
    git -C "$WORK2" commit -m "remote commit" >/dev/null 2>&1
    git -C "$WORK2" push origin main >/dev/null 2>&1

    # Fetch in the primary working clone without merging.
    git -C "$WORK_DIR" fetch origin >/dev/null 2>&1

    run git_behind_count "$WORK_DIR" "origin/main"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "git_behind_count: 0 when remote ref absent (offline-safe)" {
    run git_behind_count "$WORK_DIR" "origin/nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ── git_is_dirty ──

@test "git_is_dirty: returns 1 (false) on clean working tree" {
    run git_is_dirty "$WORK_DIR"
    [ "$status" -eq 1 ]
}

@test "git_is_dirty: returns 0 (true) when file modified" {
    printf "dirty\n" >> "$WORK_DIR/file.txt"
    run git_is_dirty "$WORK_DIR"
    [ "$status" -eq 0 ]
}

@test "git_is_dirty: returns 0 (true) when untracked file added" {
    printf "new\n" > "$WORK_DIR/newfile.txt"
    run git_is_dirty "$WORK_DIR"
    [ "$status" -eq 0 ]
}

# ── git_stash_save + git_stash_pop ──

@test "git_stash_save: returns 1 on clean tree (nothing to stash)" {
    run git_stash_save "$WORK_DIR" "test stash"
    [ "$status" -eq 1 ]
}

@test "git_stash_save: returns stash ref when changes exist" {
    printf "stashed\n" >> "$WORK_DIR/file.txt"
    run git_stash_save "$WORK_DIR" "my stash"
    [ "$status" -eq 0 ]
    [[ "$output" == "stash@{0}" ]]
}

@test "git_stash_pop: restores stashed changes" {
    printf "stashed content\n" >> "$WORK_DIR/file.txt"
    git_stash_save "$WORK_DIR" "pop test" >/dev/null

    # Working tree is clean after stash
    run git_is_dirty "$WORK_DIR"
    [ "$status" -eq 1 ]

    # Pop should restore changes
    run git_stash_pop "$WORK_DIR" "stash@{0}"
    [ "$status" -eq 0 ]

    run git_is_dirty "$WORK_DIR"
    [ "$status" -eq 0 ]
}

# ── git_conflicted_files ──

@test "git_conflicted_files: empty on clean tree" {
    run git_conflicted_files "$WORK_DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git_conflicted_files: lists conflicted file after manual conflict injection" {
    # Set up a conflict: two branches modify the same line differently.
    git -C "$WORK_DIR" checkout -b feature >/dev/null 2>&1
    printf "feature line\n" > "$WORK_DIR/conflict.txt"
    git -C "$WORK_DIR" add conflict.txt
    git -C "$WORK_DIR" commit -m "feature" >/dev/null 2>&1

    git -C "$WORK_DIR" checkout main >/dev/null 2>&1
    printf "main line\n" > "$WORK_DIR/conflict.txt"
    git -C "$WORK_DIR" add conflict.txt
    git -C "$WORK_DIR" commit -m "main" >/dev/null 2>&1

    # Merge with conflict (-X theirs would resolve, so use plain merge which fails)
    git -C "$WORK_DIR" merge feature >/dev/null 2>&1 || true

    run git_conflicted_files "$WORK_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"conflict.txt"* ]]
}

# ── git_resolve_file ──

@test "git_resolve_file ours: resolves conflict by keeping local version" {
    # Create a conflict scenario
    git -C "$WORK_DIR" checkout -b br1 >/dev/null 2>&1
    printf "branch one\n" > "$WORK_DIR/rc.txt"
    git -C "$WORK_DIR" add rc.txt
    git -C "$WORK_DIR" commit -m "br1" >/dev/null 2>&1

    git -C "$WORK_DIR" checkout main >/dev/null 2>&1
    printf "main line\n" > "$WORK_DIR/rc.txt"
    git -C "$WORK_DIR" add rc.txt
    git -C "$WORK_DIR" commit -m "main rc" >/dev/null 2>&1

    git -C "$WORK_DIR" merge br1 >/dev/null 2>&1 || true

    # Resolve via ours
    run git_resolve_file "$WORK_DIR" "rc.txt" "ours"
    [ "$status" -eq 0 ]

    # File should contain "main line"
    [[ "$(cat "$WORK_DIR/rc.txt")" == "main line" ]]
}

@test "git_resolve_file theirs: resolves conflict by taking remote version" {
    git -C "$WORK_DIR" checkout -b br2 >/dev/null 2>&1
    printf "branch two\n" > "$WORK_DIR/rt.txt"
    git -C "$WORK_DIR" add rt.txt
    git -C "$WORK_DIR" commit -m "br2" >/dev/null 2>&1

    git -C "$WORK_DIR" checkout main >/dev/null 2>&1
    printf "main rt\n" > "$WORK_DIR/rt.txt"
    git -C "$WORK_DIR" add rt.txt
    git -C "$WORK_DIR" commit -m "main rt" >/dev/null 2>&1

    git -C "$WORK_DIR" merge br2 >/dev/null 2>&1 || true

    run git_resolve_file "$WORK_DIR" "rt.txt" "theirs"
    [ "$status" -eq 0 ]

    [[ "$(cat "$WORK_DIR/rt.txt")" == "branch two" ]]
}
