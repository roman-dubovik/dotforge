#!/usr/bin/env bats

setup() {
    # Mock bw command
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/bw" <<'MOCKEOF'
#!/usr/bin/env bash
case "$1" in
    "status") echo '{"status":"unlocked"}' ;;
    "get")
        if [[ "$2" == "attachment" ]]; then
            echo "fake-key-content"
        fi
        ;;
    *) exit 1 ;;
esac
MOCKEOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/bw"

    source "$BATS_TEST_DIRNAME/../../lib/secrets.sh"
}

@test "bw_is_unlocked detects unlocked state" {
    run bw_is_unlocked
    [ "$status" -eq 0 ]
}

@test "bw_get_attachment writes to file" {
    local out="$BATS_TEST_TMPDIR/key"
    run bw_get_attachment "id_ed25519" "dotforge-ssh-personal" "$out"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    [ "$(cat "$out")" = "fake-key-content" ]
}
