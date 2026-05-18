#!/usr/bin/env bats
# Integration tests for dot-apply.sh --enable/--disable flag handling.
# chezmoi and doctor are mocked to prevent real mutations and isolate flag logic.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dot-apply.sh"

setup() {
    # Redirect HOME so no real ~/.config is touched.
    # DOTFORGE_STATE_FILE and DOTFORGE_CHEZMOI_TOML are overridden so the real
    # script writes to tmp paths instead of ~/.config.
    export HOME="$BATS_TEST_TMPDIR"
    export DOTFORGE_STATE_FILE="$BATS_TEST_TMPDIR/.config/dotforge/state.toml"
    export DOTFORGE_CHEZMOI_TOML="$BATS_TEST_TMPDIR/.config/chezmoi/chezmoi.toml"

    # Mock chezmoi on PATH so apply/diff don't mutate real dotfiles.
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
}

# Helper: invoke the real dot-apply.sh script.
# Tests that assert on file content (not exit code) call run_apply directly
# and use || true since the real doctor.sh runs in an isolated HOME.
# Tests that assert on exit code use: run bash "$SCRIPT" ...
run_apply() {
    bash "$SCRIPT" "$@" || true
}

# ── --enable single feature ──

@test "dot-apply --enable=docker_desktop: creates state.toml (real script)" {
    # Doctor will fail in isolated HOME — assert on file, not exit code.
    bash "$SCRIPT" --enable=docker_desktop || true
    [ -f "$DOTFORGE_STATE_FILE" ]
}

@test "dot-apply --enable=docker_desktop: sets feature to true (real script)" {
    bash "$SCRIPT" --enable=docker_desktop || true
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.docker_desktop
    [ "$output" = "true" ]
}

@test "dot-apply --disable=office_suite: sets feature to false (real script)" {
    bash "$SCRIPT" --disable=office_suite || true
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.office_suite
    [ "$output" = "false" ]
}

# ── --enable comma-separated CSV ──

@test "dot-apply --disable=office_suite,media_tools: disables both" {
    run_apply --disable=office_suite,media_tools
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.office_suite
    [ "$output" = "false" ]
    run state_get features.media_tools
    [ "$output" = "false" ]
}

@test "dot-apply --enable=office_suite,media_tools: enables both" {
    run_apply --enable=office_suite,media_tools
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.office_suite
    [ "$output" = "true" ]
    run state_get features.media_tools
    [ "$output" = "true" ]
}

# ── Repeated flags ──

@test "dot-apply --enable=A --disable=B (repeated flags): both applied" {
    run_apply --enable=office_suite --disable=media_tools
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.office_suite
    [ "$output" = "true" ]
    run state_get features.media_tools
    [ "$output" = "false" ]
}

# ── Unknown feature → exit 2 ──

@test "dot-apply --enable=nonexistent_flag: exit 2" {
    run bash "$SCRIPT" --enable=nonexistent_flag
    [ "$status" -eq 2 ]
}

@test "dot-apply --enable=nonexistent_flag: error message lists valid features" {
    run bash "$SCRIPT" --enable=nonexistent_flag
    [[ "$output" == *"unknown feature: nonexistent_flag"* ]]
    [[ "$output" == *"docker_desktop"* ]]
    [[ "$output" == *"ai_assistants"* ]]
    [[ "$output" == *"office_suite"* ]]
}

@test "dot-apply --enable=bad_flag: exit 2 (unknown flag)" {
    run bash "$SCRIPT" --enable=bad_flag
    [ "$status" -eq 2 ]
}

# ── state.toml lifecycle (AC 1) ──

@test "dot-apply --enable on fresh machine: creates state.toml with all six features" {
    [ ! -f "$DOTFORGE_STATE_FILE" ]
    run_apply --enable=docker_desktop
    [ -f "$DOTFORGE_STATE_FILE" ]
    for feat in docker_desktop ai_assistants vpn_suite office_suite media_tools design_tools; do
        grep -q "$feat" "$DOTFORGE_STATE_FILE"
    done
}

# ── chezmoi.toml sync (AC 6) ──

@test "dot-apply --enable=X: syncs into chezmoi.toml" {
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"

[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = false
    media_tools = true
    design_tools = true
TOML

    run_apply --enable=office_suite

    run grep "office_suite" "$DOTFORGE_CHEZMOI_TOML"
    [[ "$output" == *"true"* ]]
}

# ── State file is syntactically valid after mutation ──

@test "dot-apply --disable CSV: state.toml has [features] header after mutation" {
    run_apply --disable=office_suite,media_tools
    grep -q "^\[features\]" "$DOTFORGE_STATE_FILE"
}

# ── Real script: --dry-run does not create state.toml ──

@test "dot-apply --dry-run: does not create state.toml (real script)" {
    # --dry-run branches before state code; use real script with mocked chezmoi
    run bash "$SCRIPT" --dry-run
    [ ! -f "$DOTFORGE_STATE_FILE" ]
}

@test "dot-apply --dry-run --enable=docker_desktop: state.toml NOT created, exit 0" {
    run bash "$SCRIPT" --dry-run --enable=docker_desktop
    [ "$status" -eq 0 ]
    [ ! -f "$DOTFORGE_STATE_FILE" ]
}

@test "dot-apply --dry-run --enable=docker_desktop: prints 'would enable' message" {
    run bash "$SCRIPT" --dry-run --enable=docker_desktop
    [[ "$output" == *"would enable: docker_desktop"* ]]
}

# ── Same-feature enable+disable conflict → exit 2 ──

@test "dot-apply --enable=X --disable=X: exit 2 on same-feature conflict" {
    run bash "$SCRIPT" --enable=docker_desktop --disable=docker_desktop
    [ "$status" -eq 2 ]
}

@test "dot-apply --enable=X --disable=X: error message names the conflicting feature" {
    run bash "$SCRIPT" --enable=docker_desktop --disable=docker_desktop
    [[ "$output" == *"conflicting --enable and --disable for feature: docker_desktop"* ]]
}

# ── Real script: unknown argument still exits 2 ──

@test "dot-apply unknown arg: real script exits 2" {
    run bash "$SCRIPT" --totally-unknown-flag
    [ "$status" -eq 2 ]
}
