#!/usr/bin/env bats
# Integration tests for scripts/dot-status.sh.
#
# Strategy:
#   - DOTFORGE_CHEZMOI_REPO → local temp git repo fixture (no chezmoi needed).
#   - DOTFORGE_SCANNER_FILES → colon-separated override.
#   - DOTFORGE_DOCTOR_SCRIPT → stub doctor for fast/deterministic doctor section.
#   - chezmoi binary is mocked in PATH (for --fetch path and source-path fallback).

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dot-status.sh"

# ── Setup ──

setup() {
    # Create a bare "remote" and a local "work" clone (acts as chezmoi source repo).
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    CHEZMOI_REPO="$BATS_TEST_TMPDIR/chezmoi-src"

    git init --bare "$REMOTE_DIR" >/dev/null 2>&1
    git clone "$REMOTE_DIR" "$CHEZMOI_REPO" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" config user.email "test@test.local"
    git -C "$CHEZMOI_REPO" config user.name  "Test"

    # Initial commit so HEAD and origin/main exist
    printf "init\n" > "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "init" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" push origin HEAD:main >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" checkout -b main >/dev/null 2>&1 || true
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

    # Mock doctor: default emits one OK line, exits 0
    MOCK_DOCTOR="$BATS_TEST_TMPDIR/mock-doctor.sh"
    cat > "$MOCK_DOCTOR" <<'DOCTOR'
#!/usr/bin/env bash
printf "[OK]   chezmoi-state          ok\n"
exit 0
DOCTOR
    chmod +x "$MOCK_DOCTOR"

    # Mock chezmoi (no-op; source-path fallback)
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<MOCK
#!/usr/bin/env bash
if [[ "\${1:-}" == "source-path" ]]; then
    printf "%s\n" "$CHEZMOI_REPO"
fi
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    export DOTFORGE_CHEZMOI_REPO="$CHEZMOI_REPO"
    export DOTFORGE_SCANNER_FILES=""
    export DOTFORGE_BRANCH="main"
    export DOTFORGE_DOCTOR_SCRIPT="$MOCK_DOCTOR"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
}

# ── Usage errors ──

@test "dot status: unknown argument exits 2" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "dot status --help: exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "dot status --help: mentions --fetch" {
    run bash "$SCRIPT" --help
    [[ "$output" == *"--fetch"* ]]
}

# ── Non-destructive: no fetch without explicit --fetch ──

@test "dot status: does not invoke 'chezmoi git fetch' without --fetch" {
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<MOCK
#!/usr/bin/env bash
if [[ "\${2:-}" == "--" && "\${3:-}" == "fetch" ]]; then
    printf "UNEXPECTED FETCH\n" >&2
    exit 99
fi
if [[ "\${1:-}" == "source-path" ]]; then printf "%s\n" "$CHEZMOI_REPO"; fi
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    run bash "$SCRIPT"
    [[ "$output" != *"UNEXPECTED FETCH"* ]]
    [ "$status" -ne 99 ]
}

# ── ahead / behind ──

@test "dot status: shows 'commits ahead: 0' when up-to-date" {
    run bash "$SCRIPT"
    [[ "$output" == *"commits ahead:     0"* ]]
}

@test "dot status: shows 'commits behind: 0' when up-to-date" {
    run bash "$SCRIPT"
    [[ "$output" == *"commits behind:    0"* ]]
}

@test "dot status: exits 0 when everything in-sync" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "dot status: shows ahead count 1 after local commit" {
    printf "local\n" >> "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local" >/dev/null 2>&1

    run bash "$SCRIPT"
    [[ "$output" == *"commits ahead:     1"* ]]
}

@test "dot status: exits 1 when commits ahead > 0" {
    printf "local2\n" >> "$CHEZMOI_REPO/file.txt"
    git -C "$CHEZMOI_REPO" add file.txt
    git -C "$CHEZMOI_REPO" commit -m "local2" >/dev/null 2>&1

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "dot status: shows behind count 1 after remote advance" {
    WORK2="$BATS_TEST_TMPDIR/work2"
    git clone "$REMOTE_DIR" "$WORK2" >/dev/null 2>&1
    git -C "$WORK2" config user.email "test@test.local"
    git -C "$WORK2" config user.name  "Test"
    printf "remote advance\n" >> "$WORK2/file.txt"
    git -C "$WORK2" add file.txt
    git -C "$WORK2" commit -m "remote" >/dev/null 2>&1
    git -C "$WORK2" push origin main >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    run bash "$SCRIPT"
    [[ "$output" == *"commits behind:    1"* ]]
}

@test "dot status: exits 1 when commits behind > 0" {
    WORK2="$BATS_TEST_TMPDIR/work2b"
    git clone "$REMOTE_DIR" "$WORK2" >/dev/null 2>&1
    git -C "$WORK2" config user.email "test@test.local"
    git -C "$WORK2" config user.name  "Test"
    printf "remote2\n" >> "$WORK2/file.txt"
    git -C "$WORK2" add file.txt
    git -C "$WORK2" commit -m "remote2" >/dev/null 2>&1
    git -C "$WORK2" push origin main >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

# ── working tree clean / dirty ──

@test "dot status: shows 'working tree: clean' on clean repo" {
    run bash "$SCRIPT"
    [[ "$output" == *"working tree:      clean"* ]]
}

@test "dot status: shows 'working tree: dirty' when chezmoi repo has changes" {
    printf "dirty\n" >> "$CHEZMOI_REPO/file.txt"

    run bash "$SCRIPT"
    [[ "$output" == *"working tree:      dirty"* ]]
}

@test "dot status: exits 1 when working tree is dirty" {
    printf "dirty2\n" >> "$CHEZMOI_REPO/file.txt"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

# ── scanner outputs ──

@test "dot status: 'scanner outputs: none uncommitted' when DOTFORGE_SCANNER_FILES empty" {
    export DOTFORGE_SCANNER_FILES=""
    run bash "$SCRIPT"
    [[ "$output" == *"scanner outputs:   none uncommitted"* ]]
}

# ── dot doctor summary ──

@test "dot status: shows PASS when doctor exits 0 with no WARN/FAIL" {
    run bash "$SCRIPT"
    [[ "$output" == *"dot doctor:        PASS"* ]]
}

@test "dot status: shows WARN when doctor emits WARN line" {
    cat > "$BATS_TEST_TMPDIR/mock-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
printf "[OK]   chezmoi-state          ok\n"
printf "[WARN] brewfile               outdated\n"
exit 1
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-doctor.sh"
    export DOTFORGE_DOCTOR_SCRIPT="$BATS_TEST_TMPDIR/mock-doctor.sh"

    run bash "$SCRIPT"
    [[ "$output" == *"dot doctor:        WARN"* ]]
}

@test "dot status: exits 1 when doctor has WARN" {
    cat > "$BATS_TEST_TMPDIR/mock-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
printf "[OK]   chezmoi-state          ok\n"
printf "[WARN] brewfile               outdated\n"
exit 1
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-doctor.sh"
    export DOTFORGE_DOCTOR_SCRIPT="$BATS_TEST_TMPDIR/mock-doctor.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "dot status: shows FAIL when doctor emits FAIL line" {
    cat > "$BATS_TEST_TMPDIR/mock-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
printf "[FAIL] ssh-keys               missing\n"
exit 2
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-doctor.sh"
    export DOTFORGE_DOCTOR_SCRIPT="$BATS_TEST_TMPDIR/mock-doctor.sh"

    run bash "$SCRIPT"
    [[ "$output" == *"dot doctor:        FAIL"* ]]
}

# ── remote ref missing (offline) ──

@test "dot status: shows 'unknown' when remote ref does not exist" {
    export DOTFORGE_BRANCH="nonexistent-branch-xyz"
    run bash "$SCRIPT"
    [[ "$output" == *"unknown (remote ref not found"* ]]
}

# ── output structure ──

@test "dot status: output includes remote line" {
    run bash "$SCRIPT"
    [[ "$output" == *"remote:"* ]]
}

@test "dot status: output includes origin/main in remote line" {
    run bash "$SCRIPT"
    [[ "$output" == *"origin/main"* ]]
}

# ── FIX 9 (e): --fetch invokes chezmoi fetch (sentinel-file test) ──

@test "dot status --fetch: invokes chezmoi git fetch" {
    SENTINEL="$BATS_TEST_TMPDIR/fetch-was-called"
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<MOCK
#!/usr/bin/env bash
if [[ "\${2:-}" == "--" && "\${3:-}" == "fetch" ]]; then
    touch "$SENTINEL"
    # Execute the actual fetch so counts remain valid
    shift; shift
    exec git -C "$CHEZMOI_REPO" "\$@"
fi
if [[ "\${1:-}" == "source-path" ]]; then printf "%s\n" "$CHEZMOI_REPO"; fi
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    run bash "$SCRIPT" --fetch
    [ -f "$SENTINEL" ]
}

# ── FIX 9 (f): uncommitted scanner outputs lists the branch ──

@test "dot status: uncommitted scanner file is reported" {
    # REPO_ROOT is hardcoded in the script as two levels up from scripts/dot-status.sh.
    # To test the scanner-output path we need the file to live under that real REPO_ROOT.
    # We use a wrapper script that first cd's into a temp dir and adjusts PATH so that
    # REPO_ROOT computation is stable, then creates the scanner file and invokes dot-status.
    #
    # Simplest approach: create a thin wrapper that overrides REPO_ROOT via the argument
    # that SCRIPT_DIR derives from BASH_SOURCE[0].  We copy the script to a path where
    # two levels up is our CHEZMOI_REPO.

    # Arrange directory layout: FAKE_DOTFORGE/scripts/dot-status.sh
    #   so that REPO_ROOT = FAKE_DOTFORGE
    FAKE_DOTFORGE="$BATS_TEST_TMPDIR/fake-dotforge"
    mkdir -p "$FAKE_DOTFORGE/scripts/lib"
    cp "$SCRIPT" "$FAKE_DOTFORGE/scripts/dot-status.sh"
    # Copy lib/ dependencies
    cp /Users/romandubovik/Documents/Projects/dotforge/scripts/lib/git-state.sh \
       "$FAKE_DOTFORGE/scripts/lib/git-state.sh"
    # Create a lib/log.sh stub in the fake dotforge root
    mkdir -p "$FAKE_DOTFORGE/lib"
    cat > "$FAKE_DOTFORGE/lib/log.sh" <<'LOG'
#!/usr/bin/env bash
log_info()    { printf "→ %s\n" "$*"; }
log_warn()    { printf "! %s\n" "$*" >&2; }
log_section() { printf "\n── %s ──\n" "$*"; }
LOG

    # Create a scanner file tracked by CHEZMOI_REPO (used as the git repo for status checks)
    SCANNER_FILE="$CHEZMOI_REPO/cli-globals.txt"
    printf "initial\n" > "$SCANNER_FILE"
    git -C "$CHEZMOI_REPO" add cli-globals.txt
    git -C "$CHEZMOI_REPO" commit -m "add scanner file" >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" push origin main >/dev/null 2>&1
    git -C "$CHEZMOI_REPO" fetch origin >/dev/null 2>&1

    # Modify it without committing
    printf "modified\n" >> "$SCANNER_FILE"

    # Build a DOTFORGE_SCANNER_FILES path that starts with FAKE_DOTFORGE so the strip works.
    # The script does: rel="${sf#"${REPO_ROOT}"/}"
    # We need sf to begin with FAKE_DOTFORGE.
    # But the actual file lives in CHEZMOI_REPO.  Create a symlink inside FAKE_DOTFORGE:
    mkdir -p "$FAKE_DOTFORGE/scanner-data"
    ln -sf "$SCANNER_FILE" "$FAKE_DOTFORGE/cli-globals.txt"

    # git -C "$FAKE_DOTFORGE" needs to know about this file.
    # Re-use CHEZMOI_REPO as the underlying git repo by symlinking .git:
    ln -sf "$CHEZMOI_REPO/.git" "$FAKE_DOTFORGE/.git"

    run bash "$FAKE_DOTFORGE/scripts/dot-status.sh" \
        2>&1 <<< ""
    # We don't assert exit status here because other divergences may be present.
    # What we assert: the scanner section mentions cli-globals.txt.
    [[ "$output" == *"cli-globals.txt"* ]]
}

# ── FIX 9 (g): doctor crash → ERROR line + DIVERGED=1 + exit 1 ──

@test "dot status: doctor crash with no output exits 1 with ERROR line" {
    cat > "$BATS_TEST_TMPDIR/mock-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
# No parseable output; just exit non-zero
exit 42
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-doctor.sh"
    export DOTFORGE_DOCTOR_SCRIPT="$BATS_TEST_TMPDIR/mock-doctor.sh"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"42"* ]]
}
