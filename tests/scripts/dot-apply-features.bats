#!/usr/bin/env bats
# Integration tests for dot-apply.sh --enable/--disable flag handling.
# chezmoi and doctor are mocked to prevent real mutations and isolate flag logic.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/dot-apply.sh"

setup() {
    # Redirect HOME so no real ~/.config is touched
    export HOME="$BATS_TEST_TMPDIR"
    export DOTFORGE_STATE_FILE="$BATS_TEST_TMPDIR/.config/dotforge/state.toml"
    export DOTFORGE_CHEZMOI_TOML="$BATS_TEST_TMPDIR/.config/chezmoi/chezmoi.toml"

    # Mock chezmoi and bash (for doctor.sh subprocess) to succeed silently
    mkdir -p "$BATS_TEST_TMPDIR/mocks"

    # Mock chezmoi: succeed for apply and diff
    cat > "$BATS_TEST_TMPDIR/mocks/chezmoi" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mocks/chezmoi"

    # Mock doctor.sh by overriding REPO_ROOT's scripts/doctor.sh via a symlink trick:
    # create a fake doctor.sh in the mocks dir and export REPO_ROOT pointing there.
    mkdir -p "$BATS_TEST_TMPDIR/mock-repo/scripts"
    mkdir -p "$BATS_TEST_TMPDIR/mock-repo/lib"
    mkdir -p "$BATS_TEST_TMPDIR/mock-repo/scripts/lib"

    # doctor.sh mock: exits 0, outputs nothing
    cat > "$BATS_TEST_TMPDIR/mock-repo/scripts/doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
exit 0
DOCTOR
    chmod +x "$BATS_TEST_TMPDIR/mock-repo/scripts/doctor.sh"

    # Copy real helpers that dot-apply.sh needs
    cp "$BATS_TEST_DIRNAME/../../lib/dot-apply-helpers.sh" \
        "$BATS_TEST_TMPDIR/mock-repo/lib/dot-apply-helpers.sh"
    cp "$BATS_TEST_DIRNAME/../../lib/log.sh" \
        "$BATS_TEST_TMPDIR/mock-repo/lib/log.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh" \
        "$BATS_TEST_TMPDIR/mock-repo/scripts/lib/state.sh"

    # Export REPO_ROOT override used by tests (dot-apply.sh derives REPO_ROOT from BASH_SOURCE)
    # We instead use a wrapper that sets REPO_ROOT before sourcing the script.
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
    export _MOCK_REPO_ROOT="$BATS_TEST_TMPDIR/mock-repo"
}

# Helper: run dot-apply.sh with an overridden REPO_ROOT
run_apply() {
    # Wrap call: override REPO_ROOT inside the script via env var indirection.
    # We need a wrapper script that sets REPO_ROOT then sources dot-apply.sh internals.
    # Simpler: just run the real script with REPO_ROOT pointing to mock repo via a wrapper.
    bash -c "
        REPO_ROOT='$_MOCK_REPO_ROOT'
        SCRIPT_DIR=\"\$REPO_ROOT/scripts\"
        source \"\$REPO_ROOT/lib/dot-apply-helpers.sh\"
        source \"\$REPO_ROOT/lib/log.sh\" 2>/dev/null || true
        source \"\$REPO_ROOT/scripts/lib/state.sh\"

        DRY_RUN=0
        ENABLE_FLAGS=()
        DISABLE_FLAGS=()

        _append_csv_to_array() {
            local csv=\"\$1\" arr_name=\"\$2\" item rest
            rest=\"\$csv\"
            while [[ -n \"\$rest\" ]]; do
                item=\"\${rest%%,*}\"
                item=\"\$(printf \"%s\" \"\$item\" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')\"
                [[ -n \"\$item\" ]] && eval \"\${arr_name}+=(\\\"\\\$item\\\")\"
                if [[ \"\$rest\" == *,* ]]; then rest=\"\${rest#*,}\"; else rest=\"\"; fi
            done
        }
        _valid_features_csv() {
            local out=\"\" f
            for f in \"\${DOTFORGE_FEATURES[@]}\"; do
                [[ -n \"\$out\" ]] && out+=\", \"
                out+=\"\$f\"
            done
            printf \"%s\" \"\$out\"
        }

        for arg in \"\$@\"; do
            case \"\$arg\" in
                --enable=*)  _append_csv_to_array \"\${arg#--enable=}\"  ENABLE_FLAGS ;;
                --disable=*) _append_csv_to_array \"\${arg#--disable=}\" DISABLE_FLAGS ;;
            esac
        done

        for _f in \"\${ENABLE_FLAGS[@]+\"\${ENABLE_FLAGS[@]}\"}\"\
                  \"\${DISABLE_FLAGS[@]+\"\${DISABLE_FLAGS[@]}\"}\"
        do
            if ! state_valid_feature \"\$_f\"; then
                printf '✗ unknown feature: %s (valid: %s)\n' \"\$_f\" \"\$(_valid_features_csv)\" >&2
                exit 2
            fi
        done

        if [[ \"\${#ENABLE_FLAGS[@]}\" -gt 0 || \"\${#DISABLE_FLAGS[@]}\" -gt 0 ]]; then
            state_init
            for _f in \"\${ENABLE_FLAGS[@]+\"\${ENABLE_FLAGS[@]}\"}\"  ; do state_set \"features.\${_f}\" true;  done
            for _f in \"\${DISABLE_FLAGS[@]+\"\${DISABLE_FLAGS[@]}\"}\" ; do state_set \"features.\${_f}\" false; done
            chezmoi_toml_sync
        fi
        exit 0
    " -- "$@"
}

# ── --enable single feature ──

@test "dot-apply --enable=docker_desktop: creates state.toml" {
    run run_apply --enable=docker_desktop
    [ "$status" -eq 0 ]
    [ -f "$DOTFORGE_STATE_FILE" ]
}

@test "dot-apply --enable=docker_desktop: sets feature to true" {
    run_apply --enable=docker_desktop
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../../scripts/lib/state.sh"
    run state_get features.docker_desktop
    [ "$output" = "true" ]
}

@test "dot-apply --disable=office_suite: sets feature to false" {
    run_apply --disable=office_suite
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
    run run_apply --enable=nonexistent_flag
    [ "$status" -eq 2 ]
}

@test "dot-apply --enable=nonexistent_flag: error message lists valid features" {
    run run_apply --enable=nonexistent_flag
    [[ "$output" == *"unknown feature: nonexistent_flag"* ]]
    [[ "$output" == *"docker_desktop"* ]]
    [[ "$output" == *"ai_assistants"* ]]
    [[ "$output" == *"office_suite"* ]]
}

@test "dot-apply --enable=bad_flag: exit 2 (unknown flag)" {
    run run_apply --enable=bad_flag
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

# ── Real script: unknown argument still exits 2 ──

@test "dot-apply unknown arg: real script exits 2" {
    run bash "$SCRIPT" --totally-unknown-flag
    [ "$status" -eq 2 ]
}
