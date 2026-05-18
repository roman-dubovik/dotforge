#!/usr/bin/env bats
# Integration tests for scripts/dot-features.sh.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dot-features.sh"

setup() {
    export HOME="$BATS_TEST_TMPDIR"
    export DOTFORGE_STATE_FILE="$BATS_TEST_TMPDIR/.config/dotforge/state.toml"
    export DOTFORGE_CHEZMOI_TOML="$BATS_TEST_TMPDIR/.config/chezmoi/chezmoi.toml"
}

# ── Exit code ──

@test "dot features: exits 0 without state.toml" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "dot features: exits 0 with state.toml" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

# ── Output: all six features listed ──

@test "dot features: shows all six feature names" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker_desktop"* ]]
    [[ "$output" == *"ai_assistants"* ]]
    [[ "$output" == *"vpn_suite"* ]]
    [[ "$output" == *"office_suite"* ]]
    [[ "$output" == *"media_tools"* ]]
    [[ "$output" == *"design_tools"* ]]
}

# ── Source labels ──

@test "dot features: shows 'state.toml' source when state file exists" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init
    run bash "$SCRIPT"
    [[ "$output" == *"state.toml"* ]]
}

@test "dot features: shows 'default' source when neither file exists" {
    run bash "$SCRIPT"
    [[ "$output" == *"default"* ]]
}

@test "dot features: shows 'chezmoi.toml' source when only chezmoi.toml exists" {
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = false
    media_tools = true
    design_tools = true
TOML

    run bash "$SCRIPT"
    [[ "$output" == *"chezmoi.toml"* ]]
}

# ── Values reflected ──

@test "dot features: reflects true value from state.toml" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init
    state_set features.office_suite true
    run bash "$SCRIPT"
    # office_suite row should show "true"
    [[ "$output" == *"office_suite"*"true"* ]]
}

@test "dot features: reflects false value from state.toml" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init
    state_set features.docker_desktop false
    run bash "$SCRIPT"
    [[ "$output" == *"docker_desktop"*"false"* ]]
}

# ── Divergent status ──

@test "dot features: shows DIVERGENT when state.toml and chezmoi.toml disagree" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init
    state_set features.office_suite true   # state says true

    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = false
    media_tools = true
    design_tools = true
TOML
    # chezmoi says false — should report divergent

    run bash "$SCRIPT"
    [[ "$output" == *"DIVERGENT"* ]]
}

@test "dot features: shows in-sync when both sources agree" {
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    state_init

    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = false
    media_tools = true
    design_tools = true
TOML

    run bash "$SCRIPT"
    [[ "$output" == *"in-sync"* ]]
}

# ── --help ──

@test "dot features --help: exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
}

@test "dot features --help: mentions state.toml" {
    run bash "$SCRIPT" --help
    [[ "$output" == *"state.toml"* ]]
}

# ── Unknown argument ──

@test "dot features --bogus: exits 2" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}
