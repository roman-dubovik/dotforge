#!/usr/bin/env bats
# Unit tests for extract_status_labels — a pure parser for doctor.sh snapshot output.
# Sources lib/dot-apply-helpers.sh and validates:
#   - Single-word and multi-word label extraction
#   - Correct status classification (OK/WARN/FAIL)
#   - Edge case: 22-char label padding
#   - Empty file handling
#   - Error on missing file

setup() {
    # Source the helper — pure function, side-effect-free.
    source "$BATS_TEST_DIRNAME/../../lib/dot-apply-helpers.sh"
    TMPF="$BATS_TEST_TMPDIR/doctor.out"
}

# Helper to build a doctor.sh line with exact format:
# printf "%s%-6s%s %-22s %s\n" "$color" "[$status]" "$C_RESET" "$label" "$details"
# With no color, effective format: [STATUS]<pad> %-22s %s
# [OK] = 4 chars, padded to 6 with 2 spaces = "[OK]  "
# Then 1 space (separator in format string) = offset 7
# Then label (22 chars, right-padded if shorter)
# Then 1 space
# Then details.
make_status_line() {
    local status="$1"
    local label="$2"
    local details="$3"
    # Build exactly: [STATUS]<pad> <label_padded> <details>
    # [OK] is 4 chars → pad to 6 = 2 spaces
    # [WARN] is 5 chars → pad to 6 = 1 space
    # [FAIL] is 5 chars → pad to 6 = 1 space
    local pad_count=$(( 6 - ${#status} - 2 ))  # -2 for brackets
    local bracket_padded="[$status]$(printf '%*s' "$pad_count" '')"
    # Label padded to 22 chars (right-padded)
    local label_padded="$(printf '%-22s' "$label")"
    printf "%s %s %s\n" "$bracket_padded" "$label_padded" "$details"
}

# Test 1: Single-word label
@test "extract_status_labels: single-word label" {
    local line=$(make_status_line "OK" "Brewfile" "5 packages installed")
    printf "%s\n" "$line" > "$TMPF"
    run extract_status_labels "$TMPF"
    [ "$status" -eq 0 ]
    [ "$output" = "OK Brewfile" ]
}

# Test 2: Multi-word labels preserved
@test "extract_status_labels: multi-word labels preserved" {
    {
        local line1=$(make_status_line "OK" "chezmoi state" "no pending changes")
        local line2=$(make_status_line "WARN" "Login items" "differ from baseline")
        local line3=$(make_status_line "FAIL" "macOS defaults" "32 keys diverge")
        printf "%s\n" "$line1" "$line2" "$line3"
    } > "$TMPF"
    run extract_status_labels "$TMPF"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK chezmoi state"* ]]
    [[ "$output" == *"WARN Login items"* ]]
    [[ "$output" == *"FAIL macOS defaults"* ]]
}

# Test 3: All three statuses in one file
@test "extract_status_labels: all three statuses extracted independently" {
    {
        local line1=$(make_status_line "OK" "Brewfile" "installed")
        local line2=$(make_status_line "WARN" "chezmoi state" "outdated")
        local line3=$(make_status_line "FAIL" "SSH keys" "missing")
        printf "%s\n" "$line1" "$line2" "$line3"
    } > "$TMPF"
    run extract_status_labels "$TMPF"
    [ "$status" -eq 0 ]
    local line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 3 ]
    # Verify each status appears exactly once
    [[ "$output" == *"OK Brewfile"* ]]
    [[ "$output" == *"WARN chezmoi state"* ]]
    [[ "$output" == *"FAIL SSH keys"* ]]
}

# Test 4: Label exactly 22 chars (edge of padding) — no truncation
@test "extract_status_labels: 22-char label no truncation" {
    # Create a 22-char label: "x" × 22
    local label_22=$(printf 'a%.0s' {1..22})
    [ ${#label_22} -eq 22 ]
    local line=$(make_status_line "OK" "$label_22" "details")
    printf "%s\n" "$line" > "$TMPF"
    run extract_status_labels "$TMPF"
    [ "$status" -eq 0 ]
    # Output should be "OK <label_22>" with trailing spaces stripped
    [ "$output" = "OK $label_22" ]
}

# Test 5: File with no status lines (comments, blanks only)
@test "extract_status_labels: file with no status lines" {
    {
        printf "# This is a comment\n"
        printf "\n"
        printf "  # indented comment\n"
        printf "\n"
    } > "$TMPF"
    run extract_status_labels "$TMPF"
    [ "$status" -eq 0 ]
    [ -z "$output" ]  # Empty output expected
}

# Test 6: File missing — function should error
@test "extract_status_labels: file missing (error expected)" {
    local missing_file="$BATS_TEST_TMPDIR/nonexistent-doctor.out"
    rm -f "$missing_file"
    run extract_status_labels "$missing_file"
    # Function uses 'done < "$file"' which fails if file not found
    [ "$status" -ne 0 ]
}
