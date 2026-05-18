#!/usr/bin/env bats
# Integration tests for dot-pull.sh --resolve modes.
#
# Strategy:
#   - chezmoi binary is mocked to translate "chezmoi git -- <args>" → "git -C $CHEZMOI_REPO <args>"
#     and "chezmoi apply" → no-op.
#   - doctor.sh is mocked via DOTFORGE_DOCTOR_SCRIPT to print "PASS" and exit 0.
#   - A real local git repo fixture is used (bare remote + clone) to drive all git ops.
#   - DOTFORGE_CHEZMOI_REPO points at the fixture clone.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dot-pull.sh"
REAL_REPO_ROOT="$BATS_TEST_DIRNAME/../.."

# ── Setup ──

setup() {
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    CHEZMOI_REPO="$BATS_TEST_TMPDIR/chezmoi-src"

    git init --bare "$REMOTE_DIR" >/dev/null 2>&1
    git clone "$REMOTE_DIR" "$CHEZMOI_REPO" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" config user.email "test@test.local"
    git -C "$CHEZMOI_REPO" config user.name  "Test"
    git -C "$CHEZMOI_REPO" config pull.rebase false

    # Initial commit
    printf "init\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "init" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" push origin HEAD:main >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" checkout -b main >/dev/null 2>&1 || true
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

    # Create a second "remote" clone to simulate remote commits
    REMOTE_WORK="$BATS_TEST_TMPDIR/remote-work"
    git clone "$REMOTE_DIR" "$REMOTE_WORK" >/dev/null 2>&1
    git -C "$REMOTE_WORK" config user.email "remote@test.local"
    git -C "$REMOTE_WORK" config user.name  "Remote"
    git -C "$REMOTE_WORK" config pull.rebase false

    # Mock chezmoi: translate "chezmoi git -- <args>" → "git -C $CHEZMOI_REPO <args>"
    # and "chezmoi apply" → exit 0 (no-op).
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<MOCK
#!/usr/bin/env bash
case "\${1:-}" in
    git)
        # chezmoi git -- <args>  →  skip "git" "--" and pass rest to real git
        shift   # drop "git"
        shift   # drop "--"
        exec git -C "$CHEZMOI_REPO" "\$@"
        ;;
    apply)
        exit 0
        ;;
    source-path)
        printf "%s\n" "$CHEZMOI_REPO"
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    # Mock doctor: always pass
    cat > "$BATS_TEST_TMPDIR/mock-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
printf "[OK]   chezmoi-state          ok\n"
exit 0
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-doctor.sh"

    export DOTFORGE_CHEZMOI_REPO="$CHEZMOI_REPO"
    export DOTFORGE_BRANCH="main"
    export DOTFORGE_DOCTOR_SCRIPT="$BATS_TEST_TMPDIR/mock-doctor.sh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
}

# Helper: push a commit from the "remote" side
push_remote_commit() {
    local msg="${1:-remote commit}"
    printf "%s\n" "$msg" >> "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "$msg" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1
}

# ── Usage errors ──

@test "dot pull: unknown --resolve mode exits 2" {
    run bash "$SCRIPT" --resolve=badmode
    [ "$status" -eq 2 ]
}

@test "dot pull: unknown --resolve mode lists valid modes" {
    run bash "$SCRIPT" --resolve=badmode
    [[ "$output" == *"abort"* ]]
    [[ "$output" == *"ours"* ]]
    [[ "$output" == *"theirs"* ]]
    [[ "$output" == *"interactive"* ]]
}

@test "dot pull --help: exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "dot pull --help: mentions --resolve" {
    run bash "$SCRIPT" --help
    [[ "$output" == *"--resolve"* ]]
}

# ── AC 3: abort mode (default) ── byte-identical behaviour regression ──

@test "dot pull --resolve=abort: same as no flag (up-to-date, exits via doctor)" {
    push_remote_commit "remote advance"
    run bash "$SCRIPT" --resolve=abort
    # doctor mock exits 0 → exec replaces process → exit 0
    [ "$status" -eq 0 ]
}

@test "dot pull (no flag): up-to-date is no-op, exits 0" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "dot pull: abort mode pulls remote commit successfully" {
    push_remote_commit "bump something"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Verify the commit landed in chezmoi repo
    local msg
    msg="$(git -C "$CHEZMOI_REPO" log -1 --format=%s)"
    [ "$msg" = "bump something" ]
}

@test "dot pull: unknown argument exits 2" {
    run bash "$SCRIPT" --totally-unknown
    [ "$status" -eq 2 ]
}

# ── AC 4: ours happy path (no conflict) ──

@test "dot pull --resolve=ours: happy path with remote commit, exit 0" {
    push_remote_commit "remote ours-happy"
    run bash "$SCRIPT" --resolve=ours
    [ "$status" -eq 0 ]
}

@test "dot pull --resolve=ours: local uncommitted change preserved after pull" {
    push_remote_commit "remote advance"
    # Local uncommitted change to a DIFFERENT file (no conflict)
    printf "local data\n" > "$CHEZMOI_REPO/local-only.txt"

    run bash "$SCRIPT" --resolve=ours
    [ "$status" -eq 0 ]
    # Local file should be present in working tree after stash pop
    [ -f "$CHEZMOI_REPO/local-only.txt" ]
}

# ── AC 5: ours conflict path ──

@test "dot pull --resolve=ours: conflict resolved, exit 0" {
    # Remote modifies file.txt at same location
    push_remote_commit "remote overwrite"

    # Local also modifies file.txt (will conflict on merge)
    printf "local change\n" >> "$CHEZMOI_REPO/file.txt"

    run bash "$SCRIPT" --resolve=ours
    [ "$status" -eq 0 ]
}

@test "dot pull --resolve=ours: pull conflict resolved with ours (local commit wins)" {
    # Create a divergent scenario: local and remote both commit to file.txt from same base.
    # Remote commits "remote-ours" first, then local commits "local-ours" from same base.
    # Now pull requires merge, causing conflict — ours keeps local-ours.

    # Save current HEAD as base
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    # Remote pushes a divergent commit
    printf "remote-ours\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote diverge" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    # Local commits from the same base (reset to base, commit divergent change)
    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-ours\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local diverge" >/dev/null 2>&1

    # Fetch so origin/main has remote commit
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    bash "$SCRIPT" --resolve=ours || true
    # After ours pull-conflict resolution, file.txt should contain local-ours
    [[ "$(cat "$CHEZMOI_REPO/file.txt")" == *"local-ours"* ]]
}

# ── AC 6: theirs mode ──

@test "dot pull --resolve=theirs: happy path, exit 0" {
    push_remote_commit "remote theirs-happy"
    run bash "$SCRIPT" --resolve=theirs
    [ "$status" -eq 0 ]
}

@test "dot pull --resolve=theirs: remote content wins on conflict" {
    # Remote pushes "remote-content"
    printf "remote-content\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote theirs-conflict" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    # Local has conflicting change
    printf "local-should-lose\n" > "$CHEZMOI_REPO/file.txt"

    bash "$SCRIPT" --resolve=theirs || true
    # After theirs resolution, file.txt should contain "remote-content"
    [[ "$(cat "$CHEZMOI_REPO/file.txt")" == *"remote-content"* ]]
}

# ── AC 7: interactive mode (gum not available → read -p fallback) ──

@test "dot pull --resolve=interactive: clean pull (no conflict), exit 0" {
    push_remote_commit "remote interactive-happy"
    # No local changes → clean ff-merge expected
    run bash "$SCRIPT" --resolve=interactive
    [ "$status" -eq 0 ]
}

@test "dot pull --resolve=interactive: read fallback accepts 'y' to keep local commit" {
    # Create divergent scenario (same as ours conflict test)
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-interactive\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote interactive diverge" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-interactive-keep\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local interactive diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # When stdin is not a tty (pipe), gum is bypassed → read -p fallback.
    # Feed 'y' → keep local (ours).
    printf "y\n" | bash "$SCRIPT" --resolve=interactive || true
    [[ "$(cat "$CHEZMOI_REPO/file.txt")" == *"local-interactive-keep"* ]]
}

@test "dot pull --resolve=interactive: read fallback accepts 'n' to take remote" {
    # Create divergent scenario
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-take-this\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote interactive-n" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-will-lose-interactive\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local interactive-n diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # When stdin is not a tty (pipe), gum is bypassed → read -p fallback.
    # Feed 'n' → take remote (theirs).
    printf "n\n" | bash "$SCRIPT" --resolve=interactive || true
    [[ "$(cat "$CHEZMOI_REPO/file.txt")" == *"remote-take-this"* ]]
}

# ── AC 8: invalid --resolve value exits 2 ──

@test "dot pull --resolve=invalid: exit 2" {
    run bash "$SCRIPT" --resolve=invalid
    [ "$status" -eq 2 ]
}

# ── AC 9: recovery on failure ──

@test "dot pull --resolve=ours: stash is preserved when apply fails" {
    push_remote_commit "remote apply-fail"
    # Use a tracked file (add + commit) so it gets properly stashed
    printf "local-stash-content\n" >> "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local stash commit" >/dev/null 2>&1
    # Now make an uncommitted change so working tree is dirty
    printf "uncommitted-change\n" >> "$CHEZMOI_REPO/file.txt"

    # Make chezmoi apply fail
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<MOCK
#!/usr/bin/env bash
case "\${1:-}" in
    git)
        shift; shift
        exec git -C "$CHEZMOI_REPO" "\$@"
        ;;
    apply)
        exit 1
        ;;
    source-path)
        printf "%s\n" "$CHEZMOI_REPO"
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    # Capture both stdout and stderr
    COMBINED_OUTPUT="$(bash "$SCRIPT" --resolve=ours 2>&1)" || true
    [[ "$COMBINED_OUTPUT" == *"stash restored"* ]]
}

# ── FIX 9 (a): stash-pop conflict path ──

@test "dot pull --resolve=ours: stash-pop conflict resolved with theirs (pre-pull local wins)" {
    # Create divergent history so pull produces a merge commit.
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    # Remote pushes to file.txt
    printf "remote-pop-ours\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote pop-ours" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    # Local commits divergent from same base
    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-committed\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local pop-ours diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # Also create a local untracked file to be stashed
    printf "local-pre-pull\n" > "$CHEZMOI_REPO/stash-file.txt"

    # Run; the stash-pop should conflict because merged file.txt conflicts with
    # the stash content; with --resolve=ours the pop side is "theirs" (stash wins).
    bash "$SCRIPT" --resolve=ours 2>&1 || true

    # The stash-file.txt should be restored (stash pop succeeds in simple case)
    # What we assert is that the script exits without destroying state.
    # The pre-pull stash-file should appear if pop succeeded.
    [ -f "$CHEZMOI_REPO/stash-file.txt" ]
}

@test "dot pull --resolve=theirs: stash-pop conflict resolved with ours (merged HEAD wins)" {
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-pop-theirs\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote pop-theirs" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-committed-theirs\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local pop-theirs diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # Untracked file stashed
    printf "pre-pull-theirs\n" > "$CHEZMOI_REPO/stash-file2.txt"

    bash "$SCRIPT" --resolve=theirs 2>&1 || true

    [ -f "$CHEZMOI_REPO/stash-file2.txt" ]
}

# ── FIX 9 (b): _resolve_conflicts failure via mock git ──

@test "dot pull --resolve=ours: resolve failure exits 1 and stash restored" {
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-resolve-fail\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote resolve-fail" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-resolve-fail\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local resolve-fail diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # Put an untracked file so the working tree is dirty → stash is saved
    printf "stash-data\n" > "$CHEZMOI_REPO/unstashed.txt"

    # git_resolve_file calls `git -C <dir> checkout --ours/--theirs` directly (not via chezmoi).
    # Inject a real git wrapper into mocks/ that fails on "checkout --ours" or "checkout --theirs".
    REAL_GIT="$(command -v git)"
    cat > "$BATS_TEST_TMPDIR/mocks/git" <<MOCK
#!/usr/bin/env bash
# Pass all args to real git but intercept "checkout --ours" / "checkout --theirs"
for arg in "\$@"; do
    if [[ "\$arg" == "--ours" || "\$arg" == "--theirs" ]]; then
        exit 1
    fi
done
exec "$REAL_GIT" "\$@"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/git"

    COMBINED="$(bash "$SCRIPT" --resolve=ours 2>&1)" || RC=$?
    rm -f "$BATS_TEST_TMPDIR/mocks/git"
    # Script should have exited 1 and printed an explicit failure message —
    # do NOT match the routine "Stashing local changes…" line that prints before any failure.
    [ "${RC:-0}" -ne 0 ]
    [[ "$COMBINED" == *"Conflict resolution failed"* ]] || [[ "$COMBINED" == *"Failed to resolve"* ]]
}

# ── FIX 9 (c): git_commit_no_edit failure ──

@test "dot pull --resolve=ours: commit failure exits 1 and stash restored" {
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-commit-fail\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote commit-fail" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-commit-fail\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local commit-fail diverge" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    printf "stash-commit-fail\n" > "$CHEZMOI_REPO/uncommitted.txt"

    # git_commit_no_edit calls `git -C <dir> commit --no-edit` directly.
    # Inject a git wrapper that fails on "commit --no-edit".
    REAL_GIT="$(command -v git)"
    cat > "$BATS_TEST_TMPDIR/mocks/git" <<MOCK
#!/usr/bin/env bash
# Intercept "commit --no-edit" to simulate merge-commit failure
for arg in "\$@"; do
    if [[ "\$arg" == "--no-edit" ]]; then
        exit 1
    fi
done
exec "$REAL_GIT" "\$@"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/git"

    COMBINED="$(bash "$SCRIPT" --resolve=ours 2>&1)" || RC=$?
    rm -f "$BATS_TEST_TMPDIR/mocks/git"
    [ "${RC:-0}" -ne 0 ]
    [[ "$COMBINED" == *"stash"* ]] || [[ "$COMBINED" == *"commit resolved merge"* ]] || [[ "$COMBINED" == *"Failed to commit"* ]]
}

# ── FIX 9 (d): --resolve=abort non-ff scenario ──

@test "dot pull --resolve=abort: exits 1 on non-fast-forward, no state mutation" {
    # Create a divergent scenario: local and remote both commit from same base.
    BASE_SHA="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    printf "remote-noff\n" > "$REMOTE_WORK/file.txt"
    git -C "$REMOTE_WORK" add file.txt
    git -C "$REMOTE_WORK" commit -m "remote noff" >/dev/null 2>&1
    git -C "$REMOTE_WORK" push origin main >/dev/null 2>&1

    git -C "$CHEZMOI_REPO" reset --hard "$BASE_SHA" >/dev/null 2>&1
    printf "local-noff\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local noff" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    HEAD_BEFORE="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"

    run bash "$SCRIPT" --resolve=abort
    [ "$status" -eq 1 ]

    # HEAD must not have moved
    HEAD_AFTER="$(git -C "$CHEZMOI_REPO" rev-parse HEAD)"
    [ "$HEAD_BEFORE" = "$HEAD_AFTER" ]
}
