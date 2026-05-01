#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/log.sh"
}

@test "log_info prints message with prefix" {
    run log_info "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "log_error prints to stderr" {
    run bash -c "source '$BATS_TEST_DIRNAME/../../lib/log.sh' && log_error 'oops' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"oops"* ]]
}

@test "log_step prints numbered step" {
    run log_step 3 8 "Installing X"
    [[ "$output" == *"[3/8]"* ]]
    [[ "$output" == *"Installing X"* ]]
}
