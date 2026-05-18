#!/usr/bin/env bats
# Unit tests for scripts/lib/state.sh — TOML feature-flag state helpers.
# All tests use DOTFORGE_STATE_FILE and DOTFORGE_CHEZMOI_TOML pointed at tmp dirs
# so no real ~/.config/ files are touched.

setup() {
    # Isolate all file I/O to a per-test temp dir
    export HOME="$BATS_TEST_TMPDIR"
    export DOTFORGE_STATE_FILE="$BATS_TEST_TMPDIR/.config/dotforge/state.toml"
    export DOTFORGE_CHEZMOI_TOML="$BATS_TEST_TMPDIR/.config/chezmoi/chezmoi.toml"

    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
}

# ── state_init ──

@test "state_init: creates state.toml with all six features" {
    run state_init
    [ "$status" -eq 0 ]
    [ -f "$DOTFORGE_STATE_FILE" ]
    # All six features present
    grep -q "docker_desktop" "$DOTFORGE_STATE_FILE"
    grep -q "ai_assistants"  "$DOTFORGE_STATE_FILE"
    grep -q "vpn_suite"      "$DOTFORGE_STATE_FILE"
    grep -q "office_suite"   "$DOTFORGE_STATE_FILE"
    grep -q "media_tools"    "$DOTFORGE_STATE_FILE"
    grep -q "design_tools"   "$DOTFORGE_STATE_FILE"
}

@test "state_init: default values correct (office_suite=false, others=true)" {
    state_init
    run grep "office_suite" "$DOTFORGE_STATE_FILE"
    [[ "$output" == *"false"* ]]

    for feat in docker_desktop ai_assistants vpn_suite media_tools design_tools; do
        val="$(grep "^${feat}" "$DOTFORGE_STATE_FILE" | sed 's/.*=[[:space:]]*//')"
        [ "$val" = "true" ]
    done
}

@test "state_init: seeds from chezmoi.toml when present (office_suite=true)" {
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"

[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = true
    media_tools = true
    design_tools = true
TOML

    state_init
    run state_get features.office_suite
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "state_init: falls back to default when feature absent from chezmoi.toml" {
    # chezmoi.toml exists but does not have office_suite
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"

[data.features]
    docker_desktop = true
TOML

    state_init
    run state_get features.office_suite
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "state_init: is idempotent (second call does not overwrite)" {
    state_init
    # Manually set a value
    sed 's/docker_desktop = true/docker_desktop = false/' "$DOTFORGE_STATE_FILE" > "${DOTFORGE_STATE_FILE}.new"
    mv "${DOTFORGE_STATE_FILE}.new" "$DOTFORGE_STATE_FILE"

    state_init  # second call — should NOT recreate the file
    run grep "docker_desktop" "$DOTFORGE_STATE_FILE"
    [[ "$output" == *"false"* ]]
}

@test "state_init: creates parent directory if missing" {
    rm -rf "$(dirname "$DOTFORGE_STATE_FILE")"
    run state_init
    [ "$status" -eq 0 ]
    [ -f "$DOTFORGE_STATE_FILE" ]
}

# ── state_get ──

@test "state_get: returns correct true value" {
    state_init
    run state_get features.docker_desktop
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "state_get: returns correct false value (office_suite default)" {
    state_init
    run state_get features.office_suite
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "state_get: returns 1 when file absent" {
    run state_get features.docker_desktop
    [ "$status" -ne 0 ]
}

@test "state_get: returns value after state_set" {
    state_init
    state_set features.docker_desktop false
    run state_get features.docker_desktop
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

# ── state_set ──

@test "state_set: enables a feature" {
    state_init
    state_set features.office_suite true
    run state_get features.office_suite
    [ "$output" = "true" ]
}

@test "state_set: disables a feature" {
    state_init
    state_set features.docker_desktop false
    run state_get features.docker_desktop
    [ "$output" = "false" ]
}

@test "state_set: does not corrupt other entries" {
    state_init
    state_set features.office_suite true

    # All other features still have their original values
    run state_get features.docker_desktop
    [ "$output" = "true" ]
    run state_get features.ai_assistants
    [ "$output" = "true" ]
    run state_get features.vpn_suite
    [ "$output" = "true" ]
    run state_get features.media_tools
    [ "$output" = "true" ]
    run state_get features.design_tools
    [ "$output" = "true" ]
}

@test "state_set: creates state.toml if absent (calls state_init)" {
    [ ! -f "$DOTFORGE_STATE_FILE" ]
    state_set features.docker_desktop false
    [ -f "$DOTFORGE_STATE_FILE" ]
    run state_get features.docker_desktop
    [ "$output" = "false" ]
}

@test "state_set: result file is syntactically valid TOML ([features] header present)" {
    state_init
    state_set features.vpn_suite false
    grep -q "^\[features\]" "$DOTFORGE_STATE_FILE"
}

@test "state_set: appends missing key inside [features] section" {
    # Create state.toml with only one feature in [features]
    mkdir -p "$(dirname "$DOTFORGE_STATE_FILE")"
    cat > "$DOTFORGE_STATE_FILE" <<'TOML'
# state.toml
[features]
docker_desktop = true
TOML

    state_set features.office_suite true

    # Both keys must be present
    run grep "docker_desktop" "$DOTFORGE_STATE_FILE"
    [[ "$output" == *"true"* ]]

    run state_get features.office_suite
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "state_set: atomic write — tmp file cleaned up on success" {
    state_init
    state_set features.vpn_suite false
    # No leftover .tmp.* files
    local count
    count="$(find "$(dirname "$DOTFORGE_STATE_FILE")" -name "*.tmp.*" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$count" -eq 0 ]
}

# ── state_list_features ──

@test "state_list_features: prints all six features" {
    state_init
    run state_list_features
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker_desktop"* ]]
    [[ "$output" == *"ai_assistants"* ]]
    [[ "$output" == *"vpn_suite"* ]]
    [[ "$output" == *"office_suite"* ]]
    [[ "$output" == *"media_tools"* ]]
    [[ "$output" == *"design_tools"* ]]
}

@test "state_list_features: format is feature=value per line" {
    state_init
    run state_list_features
    [ "$status" -eq 0 ]
    # Each non-empty line should match key=value
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"="* ]]
    done <<< "$output"
}

@test "state_list_features: reflects mutations" {
    state_init
    state_set features.office_suite true
    run state_list_features
    [[ "$output" == *"office_suite=true"* ]]
}

@test "state_list_features: emits defaults when file absent" {
    run state_list_features
    [ "$status" -eq 0 ]
    [[ "$output" == *"office_suite=false"* ]]
    [[ "$output" == *"docker_desktop=true"* ]]
}

# ── state_valid_feature ──

@test "state_valid_feature: returns 0 for known features" {
    for f in docker_desktop ai_assistants vpn_suite office_suite media_tools design_tools; do
        run state_valid_feature "$f"
        [ "$status" -eq 0 ]
    done
}

@test "state_valid_feature: returns 1 for unknown feature" {
    run state_valid_feature "nonexistent_flag"
    [ "$status" -ne 0 ]
}

# ── chezmoi_toml_sync ──

@test "chezmoi_toml_sync: no-op when chezmoi.toml absent" {
    state_init
    run chezmoi_toml_sync
    [ "$status" -eq 0 ]
}

@test "chezmoi_toml_sync: rewrites [data.features] section" {
    state_init
    state_set features.office_suite true

    # Create a minimal chezmoi.toml with [data.features]
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-machine"

[data.features]
    docker_desktop = true
    ai_assistants = true
    vpn_suite = true
    office_suite = false
    media_tools = true
    design_tools = true
TOML

    chezmoi_toml_sync

    # office_suite should now be true
    run grep "office_suite" "$DOTFORGE_CHEZMOI_TOML"
    [[ "$output" == *"true"* ]]
}

@test "chezmoi_toml_sync: preserves non-features sections" {
    state_init
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-machine"
    profile = "personal"

[data.features]
    docker_desktop = true
    office_suite = false
TOML

    chezmoi_toml_sync

    grep -q "machine_name" "$DOTFORGE_CHEZMOI_TOML"
    grep -q "profile" "$DOTFORGE_CHEZMOI_TOML"
}

@test "chezmoi_toml_sync: creates .bak file" {
    state_init
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    printf "[data.features]\n    docker_desktop = true\n" > "$DOTFORGE_CHEZMOI_TOML"

    chezmoi_toml_sync

    [ -f "${DOTFORGE_CHEZMOI_TOML}.bak" ]
}

@test "chezmoi_toml_sync: preserves unknown keys in [data.features]" {
    state_init
    state_set features.docker_desktop true

    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"

[data.features]
    docker_desktop = false
    custom_experimental = true
TOML

    chezmoi_toml_sync

    # docker_desktop should be updated to true
    run grep "docker_desktop" "$DOTFORGE_CHEZMOI_TOML"
    [[ "$output" == *"true"* ]]

    # custom_experimental should still be present and unchanged
    run grep "custom_experimental" "$DOTFORGE_CHEZMOI_TOML"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "chezmoi_toml_sync: appends [data.features] section when absent" {
    state_init

    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"
    profile = "personal"
TOML

    chezmoi_toml_sync

    # Section header must be present
    grep -q "\[data.features\]" "$DOTFORGE_CHEZMOI_TOML"

    # All known features must appear
    for feat in docker_desktop ai_assistants vpn_suite office_suite media_tools design_tools; do
        grep -q "$feat" "$DOTFORGE_CHEZMOI_TOML"
    done

    # Other sections must be preserved
    grep -q "machine_name" "$DOTFORGE_CHEZMOI_TOML"
    grep -q "profile" "$DOTFORGE_CHEZMOI_TOML"
}

@test "chezmoi_toml_sync: uses timestamped .bak when .bak already exists" {
    state_init
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    printf "[data.features]\n    docker_desktop = true\n" > "$DOTFORGE_CHEZMOI_TOML"
    # Pre-create the .bak file
    printf "old backup\n" > "${DOTFORGE_CHEZMOI_TOML}.bak"

    chezmoi_toml_sync

    # Original .bak must be untouched
    [ "$(cat "${DOTFORGE_CHEZMOI_TOML}.bak")" = "old backup" ]

    # A timestamped .bak must exist
    local ts_bak
    ts_bak="$(ls "${DOTFORGE_CHEZMOI_TOML}.bak."* 2>/dev/null | head -1)"
    [ -n "$ts_bak" ]
}

# ── _persist_feature_args (bootstrap.sh helper; tests via state.sh sourced in setup) ──

# Define the helper here for unit-testing; in bootstrap.sh it is defined inline.
# shellcheck disable=SC2317
_persist_feature_args_testable() {
    local a
    for a in "$@"; do
        case "$a" in
            --enable=*)  state_set "features.${a#--enable=}"  true  ;;
            --disable=*) state_set "features.${a#--disable=}" false ;;
        esac
    done
    chezmoi_toml_sync
}

@test "_persist_feature_args: writes state.toml and syncs chezmoi.toml" {
    mkdir -p "$(dirname "$DOTFORGE_CHEZMOI_TOML")"
    cat > "$DOTFORGE_CHEZMOI_TOML" <<'TOML'
[data]
    machine_name = "test-box"

[data.features]
    docker_desktop = true
    office_suite = false
TOML

    _persist_feature_args_testable --enable=office_suite --disable=docker_desktop

    # state.toml updated
    run state_get features.office_suite
    [ "$output" = "true" ]
    run state_get features.docker_desktop
    [ "$output" = "false" ]

    # chezmoi.toml synced
    run grep "office_suite" "$DOTFORGE_CHEZMOI_TOML"
    [[ "$output" == *"true"* ]]
    run grep "docker_desktop" "$DOTFORGE_CHEZMOI_TOML"
    [[ "$output" == *"false"* ]]
}
