#!/usr/bin/env bash
# Shared logging helpers. Source this file from scripts.

# Colors (only if stdout is a tty)
if [[ -t 1 ]]; then
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_RED=$'\033[31m'
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_GRAY=$'\033[90m'
else
    readonly COLOR_RESET="" COLOR_GREEN="" COLOR_YELLOW="" COLOR_RED="" COLOR_BLUE="" COLOR_GRAY=""
fi

log_info() {
    printf "%s→%s %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

log_ok() {
    printf "%s✓%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warn() {
    printf "%s!%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

log_error() {
    printf "%s✗%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

log_step() {
    local current="$1" total="$2"
    shift 2
    printf "%s[%s/%s]%s %s\n" "$COLOR_GRAY" "$current" "$total" "$COLOR_RESET" "$*"
}

log_section() {
    printf "\n%s── %s ──%s\n" "$COLOR_BLUE" "$*" "$COLOR_RESET"
}
