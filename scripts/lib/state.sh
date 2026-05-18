#!/usr/bin/env bash
# scripts/lib/state.sh — TOML state helpers for dotforge feature flags.
#
# Public API:
#   state_init                          # create state.toml with defaults if absent
#   state_get   features.FEATURE        # print "true" or "false"
#   state_set   features.FEATURE VALUE  # atomic in-place rewrite
#   state_list_features                 # print "feature=value" lines for all 6 flags
#   state_valid_feature  FEATURE        # return 0 if known, 1 otherwise
#   chezmoi_toml_sync                   # rewrite [data.features] in chezmoi.toml
#
# Bash 3.2 compatible: no declare -A, no mapfile, no ${var,,}.
# SIDE-EFFECT-FREE constants section only; functions do all mutation.

# ── Constants ──

# Default state file (override DOTFORGE_STATE_FILE for tests)
_STATE_DEFAULT_FILE="${HOME}/.config/dotforge/state.toml"
state_file() { printf "%s" "${DOTFORGE_STATE_FILE:-$_STATE_DEFAULT_FILE}"; }

# Chezmoi config file (override DOTFORGE_CHEZMOI_TOML for tests)
_CHEZMOI_TOML_DEFAULT="${HOME}/.config/chezmoi/chezmoi.toml"
chezmoi_toml_file() { printf "%s" "${DOTFORGE_CHEZMOI_TOML:-$_CHEZMOI_TOML_DEFAULT}"; }

# Canonical feature list and default values (parallel indexed arrays, bash 3.2 compat)
DOTFORGE_FEATURES=(docker_desktop ai_assistants vpn_suite office_suite media_tools design_tools)
DOTFORGE_FEATURE_DEFAULTS=(true          true          true      false        true         true)

# ── state_valid_feature ──
# Returns 0 if FEATURE is in DOTFORGE_FEATURES, 1 otherwise.
state_valid_feature() {
    local feature="$1" f
    for f in "${DOTFORGE_FEATURES[@]}"; do
        [[ "$f" == "$feature" ]] && return 0
    done
    return 1
}

# ── _seed_value_from_chezmoi ──
# Usage: _seed_value_from_chezmoi FEATURE
# Reads [data.features].FEATURE from chezmoi.toml.
# Prints "true" or "false" if found; prints nothing and returns 1 if absent.
_seed_value_from_chezmoi() {
    local feature="$1"
    local chezmoi_file
    chezmoi_file="$(chezmoi_toml_file)"
    [[ -f "$chezmoi_file" ]] || return 1

    local val
    val="$(awk -v feat="$feature" '
        /^\[data\.features\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^[[:space:]]*[^#[:space:]]/ {
            if (match($0, "^[[:space:]]*" feat "[[:space:]]*=[[:space:]]*")) {
                v = substr($0, RSTART + RLENGTH)
                gsub(/[[:space:]#].*$/, "", v)
                print v
                exit
            }
        }
    ' "$chezmoi_file")"

    [[ -n "$val" ]] || return 1
    printf "%s" "$val"
}

# ── state_init ──
# Creates state.toml with default values if file does not exist.
# Per-feature seed priority: chezmoi.toml [data.features] > DOTFORGE_FEATURE_DEFAULTS.
# If file exists, is a no-op.
state_init() {
    local file
    file="$(state_file)"
    [[ -f "$file" ]] && return 0

    local dir
    dir="$(dirname "$file")"
    mkdir -p "$dir"

    local tmp
    tmp="${file}.tmp.$$"

    {
        printf "# ~/.config/dotforge/state.toml\n"
        printf "# Managed by \`dot apply --enable=...\` and \`bootstrap.sh customize\`.\n"
        printf "# Manual edits to feature values will be overwritten; comments and other keys are preserved.\n"
        printf "[features]\n"
        local i
        for i in "${!DOTFORGE_FEATURES[@]}"; do
            local feat="${DOTFORGE_FEATURES[$i]}"
            local val
            if ! val="$(_seed_value_from_chezmoi "$feat")"; then
                val="${DOTFORGE_FEATURE_DEFAULTS[$i]}"
            fi
            printf "%s = %s\n" "$feat" "$val"
        done
    } > "$tmp"

    mv "$tmp" "$file"
}

# ── state_get ──
# Usage: state_get features.FEATURE
# Prints the value ("true" or "false") from state.toml.
# Returns 1 if feature not found.
state_get() {
    local key="$1"
    # key format: "features.FEATURE"
    local section feature
    section="${key%%.*}"
    feature="${key#*.}"

    local file
    file="$(state_file)"
    [[ -f "$file" ]] || return 1

    # Read only [features] section, extract matching key
    awk -v section="$section" -v feature="$feature" '
        /^\[/ { in_section = ($0 == "[" section "]") }
        in_section && /^[[:space:]]*[^#]/ {
            if (match($0, "^[[:space:]]*" feature "[[:space:]]*=[[:space:]]*")) {
                val = substr($0, RSTART + RLENGTH)
                gsub(/[[:space:]#].*$/, "", val)
                print val
                exit
            }
        }
    ' "$file"
}

# ── state_set ──
# Usage: state_set features.FEATURE VALUE
# Atomically rewrites [features] section of state.toml.
# Ensures file exists first (calls state_init).
state_set() {
    local key="$1" value="$2"
    local feature
    feature="${key#*.}"

    state_init

    local file
    file="$(state_file)"
    local tmp
    tmp="${file}.tmp.$$"

    # Rewrite: copy everything outside [features], rebuild [features] with new value.
    awk -v feature="$feature" -v newval="$value" '
        /^\[features\]/ {
            in_features = 1
            print
            next
        }
        /^\[/ && !/^\[features\]/ {
            in_features = 0
        }
        in_features && /^[[:space:]]*[^#[[:space:]]/ {
            # key = value line inside [features]
            split($0, parts, "=")
            k = parts[1]
            gsub(/[[:space:]]/, "", k)
            if (k == feature) {
                printf "%s = %s\n", feature, newval
            } else {
                print
            }
            next
        }
        { print }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# ── state_list_features ──
# Prints "feature=value" for every feature in [features] section.
state_list_features() {
    local file
    file="$(state_file)"
    [[ -f "$file" ]] || {
        # File absent: emit defaults
        local i
        for i in "${!DOTFORGE_FEATURES[@]}"; do
            printf "%s=%s\n" "${DOTFORGE_FEATURES[$i]}" "${DOTFORGE_FEATURE_DEFAULTS[$i]}"
        done
        return 0
    }

    awk '
        /^\[features\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^[[:space:]]*[^#[:space:]]/ {
            n = split($0, parts, "=")
            if (n >= 2) {
                k = parts[1]; gsub(/[[:space:]]/, "", k)
                v = parts[2]
                gsub(/^[[:space:]]+/, "", v)   # strip leading whitespace
                gsub(/[[:space:]#].*$/, "", v)  # strip trailing comment/space
                printf "%s=%s\n", k, v
            }
        }
    ' "$file"
}

# ── chezmoi_toml_sync ──
# Rewrites [data.features] section in ~/.config/chezmoi/chezmoi.toml
# using current values from state.toml.
# Creates a backup at <file>.bak before rewriting.
chezmoi_toml_sync() {
    local chezmoi_file
    chezmoi_file="$(chezmoi_toml_file)"
    [[ -f "$chezmoi_file" ]] || return 0   # nothing to sync if chezmoi.toml absent

    # Build the new [data.features] block from state.toml values.
    local new_block
    new_block="$(
        printf "[data.features]\n"
        local i f v
        for i in "${!DOTFORGE_FEATURES[@]}"; do
            f="${DOTFORGE_FEATURES[$i]}"
            v="$(state_get "features.${f}" 2>/dev/null || printf "%s" "${DOTFORGE_FEATURE_DEFAULTS[$i]}")"
            printf "    %s = %s\n" "$f" "$v"
        done
    )"

    local tmp bak
    tmp="${chezmoi_file}.tmp.$$"
    bak="${chezmoi_file}.bak"

    # Strategy: copy everything except the [data.features] section; append new block.
    # awk: skip lines from "[data.features]" until next "[" section header (exclusive).
    awk '
        /^\[data\.features\]/ { skip = 1; next }
        skip && /^\[/ { skip = 0 }
        !skip { print }
    ' "$chezmoi_file" > "$tmp"

    # Append new block
    printf "\n%s\n" "$new_block" >> "$tmp"

    # Backup then replace
    cp "$chezmoi_file" "$bak"
    mv "$tmp" "$chezmoi_file"
}
