#!/usr/bin/env bash
# Bitwarden CLI wrappers. Source from scripts that need secrets.

# Returns 0 if bw vault is unlocked (BW_SESSION valid), non-zero otherwise.
bw_is_unlocked() {
    local status_json
    status_json="$(bw status 2>/dev/null)" || return 1
    [[ "$status_json" == *'"status":"unlocked"'* ]]
}

# Ensures bw session is valid; prompts for unlock if needed.
# Sets BW_SESSION as side effect.
bw_ensure_unlocked() {
    if bw_is_unlocked; then
        return 0
    fi
    local session
    session="$(bw unlock --raw)" || {
        echo "Failed to unlock Bitwarden vault" >&2
        return 1
    }
    export BW_SESSION="$session"
}

# Downloads a Bitwarden attachment to a file.
# Args: <attachment_name> <item_name> <output_path>
bw_get_attachment() {
    local attachment="$1" item="$2" output="$3"

    # Real bw: --itemid + --output writes attachment to file directly.
    if bw get attachment "$attachment" --itemid "$(bw_item_id "$item")" --output "$output" >/dev/null 2>&1 \
        && [[ -s "$output" ]]; then
        return 0
    fi

    # Older bw / fallback: --raw streams attachment content to stdout.
    if bw get attachment "$attachment" --raw > "$output" 2>/dev/null \
        && [[ -s "$output" ]]; then
        return 0
    fi

    # Mock/legacy fallback: capture stdout from bare `bw get attachment <name>`.
    local content
    content="$(bw get attachment "$attachment" 2>/dev/null)" || return 1
    [[ -n "$content" ]] || return 1
    printf "%s" "$content" > "$output"
}

# Resolves a Bitwarden item name to its ID.
bw_item_id() {
    local name="$1"
    bw get item "$name" 2>/dev/null | yq -r '.id' 2>/dev/null || printf "%s" "$name"
}
