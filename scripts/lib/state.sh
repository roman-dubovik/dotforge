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
# Returns 1 if state file is absent OR if key is missing from file.
state_get() {
    local key="$1"
    # key format: "features.FEATURE"
    local section feature
    section="${key%%.*}"
    feature="${key#*.}"

    local file
    file="$(state_file)"
    [[ -f "$file" ]] || return 1

    # Read only [features] section, extract matching key.
    # Exits awk with code 1 if key not found (found=0 in END).
    awk -v section="$section" -v feature="$feature" '
        /^\[/ { in_section = ($0 == "[" section "]") }
        in_section && /^[[:space:]]*[^#]/ {
            if (match($0, "^[[:space:]]*" feature "[[:space:]]*=[[:space:]]*")) {
                val = substr($0, RSTART + RLENGTH)
                gsub(/[[:space:]#].*$/, "", val)
                print val
                found = 1
                exit
            }
        }
        END { if (!found) exit 1 }
    ' "$file"
}

# ── state_set ──
# Usage: state_set features.FEATURE VALUE
# Atomically updates a single key in state.toml. All other keys and sections preserved.
# If the key is absent from [features], it is appended inside the section.
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

    # Rewrite: update existing key or pass through all lines unchanged.
    awk -v feature="$feature" -v newval="$value" '
        /^\[features\]/ {
            in_features = 1
            print
            next
        }
        /^\[/ && !/^\[features\]/ {
            if (in_features && !found) {
                # Key was not found in [features]; append before next section.
                printf "%s = %s\n", feature, newval
                found = 1
            }
            in_features = 0
        }
        in_features && /^[[:space:]]*[^#[[:space:]]/ {
            # key = value line inside [features]
            split($0, parts, "=")
            k = parts[1]
            gsub(/[[:space:]]/, "", k)
            if (k == feature) {
                printf "%s = %s\n", feature, newval
                found = 1
                next
            }
        }
        { print }
        END {
            if (in_features && !found) {
                # [features] was the last section and key was missing; append now.
                printf "%s = %s\n", feature, newval
            }
        }
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
# Updates known feature keys in [data.features] of ~/.config/chezmoi/chezmoi.toml
# using current values from state.toml.  Unknown keys inside [data.features] and
# all other sections are left untouched.
# Returns 1 with a warning if chezmoi.toml is absent.
# Creates a backup at <file>.bak; if .bak already exists, uses <file>.bak.<timestamp>.
chezmoi_toml_sync() {
    local chezmoi_file
    chezmoi_file="$(chezmoi_toml_file)"
    if [[ ! -f "$chezmoi_file" ]]; then
        printf "WARN: chezmoi.toml not found at %s; skipping sync\n" "$chezmoi_file" >&2
        return 1
    fi

    # Read current feature values from state.toml (fall back to defaults).
    # Build a pipe-delimited lookup string: "feat1=val1|feat2=val2|..."
    local i f v
    local lookup=""
    for i in "${!DOTFORGE_FEATURES[@]}"; do
        f="${DOTFORGE_FEATURES[$i]}"
        v="$(state_get "features.${f}" 2>/dev/null || printf "%s" "${DOTFORGE_FEATURE_DEFAULTS[$i]}")"
        [[ -n "$lookup" ]] && lookup="${lookup}|"
        lookup="${lookup}${f}=${v}"
    done

    local tmp bak
    tmp="${chezmoi_file}.tmp.$$"
    bak="${chezmoi_file}.bak"
    [[ -e "$bak" ]] && bak="${chezmoi_file}.bak.$(date +%s)"

    # Strategy: walk the file line by line.
    # Inside [data.features], replace known-feature values in-place; pass through all
    # other lines (including unknown keys) unchanged.
    # If [data.features] is absent, append it at EOF.
    awk -v lookup="$lookup" '
        BEGIN {
            # Parse "feat1=val1|feat2=val2|..." into feats[feat] = val
            n = split(lookup, pairs, "|")
            for (j = 1; j <= n; j++) {
                eq = index(pairs[j], "=")
                if (eq > 0) {
                    k = substr(pairs[j], 1, eq - 1)
                    v = substr(pairs[j], eq + 1)
                    feats[k] = v
                }
            }
            found_section = 0
            in_df = 0
        }
        /^\[data\.features\]/ {
            in_df = 1
            found_section = 1
            print
            next
        }
        /^\[/ && in_df {
            in_df = 0
        }
        in_df && /^[[:space:]]*[^#[:space:]]/ {
            # Parse key from "  key = value" line
            eq = index($0, "=")
            if (eq > 0) {
                k = substr($0, 1, eq - 1)
                gsub(/[[:space:]]/, "", k)
                if (k in feats) {
                    # Replace with canonical indented value
                    printf "    %s = %s\n", k, feats[k]
                    next
                }
            }
            # Unknown key — pass through unchanged
            print
            next
        }
        { print }
        END {
            if (!found_section) {
                # Append [data.features] section
                printf "\n[data.features]\n"
                n = split(lookup, pairs, "|")
                for (j = 1; j <= n; j++) {
                    eq = index(pairs[j], "=")
                    if (eq > 0) {
                        k = substr(pairs[j], 1, eq - 1)
                        v = substr(pairs[j], eq + 1)
                        printf "    %s = %s\n", k, v
                    }
                }
            }
        }
    ' "$chezmoi_file" > "$tmp"

    # Backup then replace
    cp "$chezmoi_file" "$bak"
    mv "$tmp" "$chezmoi_file"
}
