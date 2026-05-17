#!/usr/bin/env bash
# Pure helper functions for dot-apply.sh — sourced by the script AND by bats tests.
# Keep this file SIDE-EFFECT-FREE: only function definitions, no top-level statements
# that mutate environment or run commands. Functions defined here must be reusable
# from any caller (script or test harness).

# Extract status and label from a doctor snapshot file.
# Output: "<STATUS> <label>" — one line per status line, status is OK/WARN/FAIL.
# Label width is hardcoded to 22 chars (doctor.sh %-22s format). New doctor
# checks must use ≤22-char labels or delta extraction will silently truncate.
extract_status_labels() {
    local file="$1"
    local line status label
    while IFS= read -r line; do
        # Match [OK], [WARN], or [FAIL] at the start; skip non-status lines.
        if [[ "$line" =~ ^\[(OK|WARN|FAIL)\] ]]; then
            status="${BASH_REMATCH[1]}"
            # Label is at fixed offset 7, width 22 (from doctor.sh %-6s + space + %-22s).
            label="${line:7:22}"
            # Strip trailing spaces from the padded label.
            label="${label%"${label##*[![:space:]]}"}"
            printf "%s %s\n" "$status" "$label"
        fi
    done < "$file"
}
