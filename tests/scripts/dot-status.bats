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
