#!/usr/bin/env bash
# Manage SSH keys stored as Bitwarden attachments.
#
# Modes:
#   add-ssh-key.sh                    # SCAN: pick from local-not-in-Bitwarden, bulk upload
#   add-ssh-key.sh <basename>         # SINGLE: upload one specific key
#   add-ssh-key.sh --list             # INVENTORY: show what's where, no changes
#
# Flags:
#   --scope profile|machine           # skip the scope picker (applies to all selected)
#   --non-interactive                 # auto-detected when no TTY
#   --force                           # append even if attachment with same name exists
#
# Bitwarden items used:
#   dotforge-ssh-<profile>            shared with every machine on this profile
#   dotforge-ssh-<profile>-<machine>  this machine only
#
# Requires: bw (with BW_SESSION exported), jq, gum (for prompts).

set -euo pipefail

BASENAME=""
SCOPE=""
INTERACTIVE=1
LIST_MODE=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope) SCOPE="$2"; shift 2 ;;
        --list)  LIST_MODE=1; shift ;;
        --force) FORCE=1; shift ;;
        --non-interactive) INTERACTIVE=0; shift ;;
        --help|-h) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$BASENAME" ]]; then
                BASENAME="$1"
            else
                echo "Unexpected: $1" >&2; exit 2
            fi
            shift ;;
    esac
done

[[ ! -t 0 ]] && INTERACTIVE=0

for cmd in bw jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

if [[ -z "${BW_SESSION:-}" ]]; then
    echo "BW_SESSION is not set." >&2
    echo "Run:  export BW_SESSION=\"\$(bw unlock --raw)\"" >&2
    exit 1
fi

# ── Read profile + machine_name from chezmoi config ──

CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
[[ -f "$CONFIG" ]] || { echo "$CONFIG not found (run 'chezmoi init' first)" >&2; exit 1; }

profile="$(grep -E '^[[:space:]]*profile[[:space:]]*=' "$CONFIG" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
machine="$(grep -E '^[[:space:]]*machine_name[[:space:]]*=' "$CONFIG" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
[[ -z "$profile" || -z "$machine" ]] && { echo "profile/machine_name missing in $CONFIG" >&2; exit 1; }

ITEM_PROFILE="dotforge-ssh-$profile"
ITEM_MACHINE="dotforge-ssh-$profile-$machine"

bw sync >/dev/null 2>&1 || true

# ── Inventory helpers ──

# Returns private-key attachment basenames (one per line) for an item.
# Empty output if the item doesn't exist.
list_keys_in_item() {
    local item="$1"
    bw get item "$item" 2>/dev/null \
        | jq -r '.attachments[]?.fileName' 2>/dev/null \
        | grep -v '\.pub$' \
        || true
}

# True if $1 appears as an exact element of "$2 $3 …".
in_array() {
    local needle="$1"; shift
    local h
    for h in "$@"; do
        [[ "$h" == "$needle" ]] && return 0
    done
    return 1
}

KEYS_PROFILE=()
while IFS= read -r f; do [[ -n "$f" ]] && KEYS_PROFILE+=("$f"); done < <(list_keys_in_item "$ITEM_PROFILE")

KEYS_MACHINE=()
while IFS= read -r f; do [[ -n "$f" ]] && KEYS_MACHINE+=("$f"); done < <(list_keys_in_item "$ITEM_MACHINE")

LOCAL_KEYS=()
while IFS= read -r f; do
    [[ -f "$f.pub" ]] || continue
    LOCAL_KEYS+=("$(basename "$f")")
done < <(find "$HOME/.ssh" -maxdepth 1 -name "id_*" -not -name "*.pub" 2>/dev/null | sort)

# ── --list ──

if (( LIST_MODE == 1 )); then
    echo "── Profile-shared ($ITEM_PROFILE) ──"
    if (( ${#KEYS_PROFILE[@]} == 0 )); then
        echo "  (empty)"
    else
        for k in "${KEYS_PROFILE[@]}"; do
            marker=""
            in_array "$k" "${LOCAL_KEYS[@]+"${LOCAL_KEYS[@]}"}" && marker="$marker [also on disk]"
            in_array "$k" "${KEYS_MACHINE[@]+"${KEYS_MACHINE[@]}"}" && marker="$marker [overridden by machine]"
            echo "  $k$marker"
        done
    fi
    echo ""
    echo "── Machine-only ($ITEM_MACHINE) ──"
    if (( ${#KEYS_MACHINE[@]} == 0 )); then
        echo "  (empty)"
    else
        for k in "${KEYS_MACHINE[@]}"; do
            marker=""
            in_array "$k" "${LOCAL_KEYS[@]+"${LOCAL_KEYS[@]}"}" && marker="$marker [also on disk]"
            in_array "$k" "${KEYS_PROFILE[@]+"${KEYS_PROFILE[@]}"}" && marker="$marker [overrides profile]"
            echo "  $k$marker"
        done
    fi
    echo ""
    echo "── Local in ~/.ssh, not in Bitwarden ──"
    missing=()
    for k in "${LOCAL_KEYS[@]+"${LOCAL_KEYS[@]}"}"; do
        if ! in_array "$k" "${KEYS_PROFILE[@]+"${KEYS_PROFILE[@]}"}" \
            && ! in_array "$k" "${KEYS_MACHINE[@]+"${KEYS_MACHINE[@]}"}"; then
            missing+=("$k")
        fi
    done
    if (( ${#missing[@]} == 0 )); then
        echo "  (none — every local key is tracked)"
    else
        for k in "${missing[@]}"; do
            echo "  $k"
        done
    fi
    exit 0
fi

# ── Decide which keys to upload ──

KEYS_TO_UPLOAD=()

if [[ -n "$BASENAME" ]]; then
    # Single-key mode
    KEYS_TO_UPLOAD+=("$BASENAME")
else
    # Scan mode
    for k in "${LOCAL_KEYS[@]+"${LOCAL_KEYS[@]}"}"; do
        if ! in_array "$k" "${KEYS_PROFILE[@]+"${KEYS_PROFILE[@]}"}" \
            && ! in_array "$k" "${KEYS_MACHINE[@]+"${KEYS_MACHINE[@]}"}"; then
            KEYS_TO_UPLOAD+=("$k")
        fi
    done

    if (( ${#KEYS_TO_UPLOAD[@]} == 0 )); then
        echo "✓ All local SSH keys are already in Bitwarden."
        echo "  Run 'add-ssh-key.sh --list' to see the layout, or pass <basename> to re-upload."
        exit 0
    fi

    if (( INTERACTIVE == 1 )); then
        command -v gum >/dev/null 2>&1 || { echo "gum is required for the multi-select" >&2; exit 1; }
        echo "Found ${#KEYS_TO_UPLOAD[@]} key(s) in ~/.ssh that aren't in Bitwarden yet."
        echo ""
        local_selected_csv="$(IFS=,; echo "${KEYS_TO_UPLOAD[*]}")"
        chosen="$(printf "%s\n" "${KEYS_TO_UPLOAD[@]}" | gum choose \
            --no-limit \
            --selected="$local_selected_csv" \
            --header "Pick keys to upload (space toggle, enter confirm):")"
        KEYS_TO_UPLOAD=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && KEYS_TO_UPLOAD+=("$line")
        done <<< "$chosen"
    fi

    if (( ${#KEYS_TO_UPLOAD[@]} == 0 )); then
        echo "Nothing selected. Exiting."
        exit 0
    fi
fi

# ── Pick scope (applies to the whole batch) ──

if [[ -z "$SCOPE" ]]; then
    if (( INTERACTIVE == 0 )); then
        echo "--scope required in non-interactive mode (profile|machine)" >&2
        exit 2
    fi
    command -v gum >/dev/null 2>&1 || { echo "gum is required for the scope picker" >&2; exit 1; }
    pick="$(gum choose --header "Where to store ${#KEYS_TO_UPLOAD[@]} key(s)?" \
        "profile  — shared with all machines using profile=$profile" \
        "machine  — only on $machine (other machines won't get it)")"
    [[ -z "$pick" ]] && { echo "Cancelled."; exit 1; }
    SCOPE="${pick%% *}"
fi

case "$SCOPE" in
    profile) ITEM_NAME="$ITEM_PROFILE" ;;
    machine) ITEM_NAME="$ITEM_MACHINE" ;;
    *) echo "Invalid scope: $SCOPE (expected: profile|machine)" >&2; exit 1 ;;
esac

# ── Find or create the target item ──

ITEM_ID="$(bw list items --search "$ITEM_NAME" 2>/dev/null \
    | jq -r --arg n "$ITEM_NAME" '.[] | select(.name == $n) | .id' \
    | head -1)"

if [[ -z "$ITEM_ID" ]]; then
    echo "→ Creating Bitwarden item '$ITEM_NAME'..."
    ITEM_ID="$(bw get template item \
        | jq --arg name "$ITEM_NAME" --arg notes "Managed by dotforge. SSH keys for $ITEM_NAME" \
            '.type = 2 | .name = $name | .notes = $notes
             | .secureNote = {"type": 0}
             | .login = {"uris": [], "username": null, "password": null, "totp": null}' \
        | bw encode \
        | bw create item \
        | jq -r '.id')"
    echo "  ✓ Created item $ITEM_ID"
fi

# Existing attachment names in this item (for duplicate detection)
EXISTING_ATTACHMENTS=()
while IFS= read -r f; do
    [[ -n "$f" ]] && EXISTING_ATTACHMENTS+=("$f")
done < <(bw get item "$ITEM_ID" | jq -r '.attachments[]?.fileName' 2>/dev/null || true)

# ── Upload loop ──

n_uploaded=0
n_skipped=0
for basename in "${KEYS_TO_UPLOAD[@]}"; do
    PRIV="$HOME/.ssh/$basename"
    PUB="$PRIV.pub"
    if [[ ! -f "$PRIV" || ! -f "$PUB" ]]; then
        echo "  ⚠ Skipping $basename — file (or .pub) missing in ~/.ssh"
        n_skipped=$((n_skipped+1))
        continue
    fi

    if in_array "$basename" "${EXISTING_ATTACHMENTS[@]+"${EXISTING_ATTACHMENTS[@]}"}"; then
        if (( FORCE == 1 )); then
            : # fall through — append
        elif (( INTERACTIVE == 1 )) && command -v gum >/dev/null 2>&1; then
            if ! gum confirm --default=No "$basename already in $ITEM_NAME. Append a duplicate attachment? (consider deleting the old one first.)"; then
                echo "  ⏭ Skipping $basename"
                n_skipped=$((n_skipped+1))
                continue
            fi
        else
            echo "  ⏭ Skipping $basename (already exists; pass --force to append)"
            n_skipped=$((n_skipped+1))
            continue
        fi
    fi

    fingerprint="$(ssh-keygen -lf "$PUB" 2>/dev/null | awk '{print $2}' || echo '?')"
    echo "→ Uploading $basename ($fingerprint)"
    bw create attachment --itemid "$ITEM_ID" --file "$PRIV" >/dev/null
    bw create attachment --itemid "$ITEM_ID" --file "$PUB" >/dev/null
    n_uploaded=$((n_uploaded+1))
done

bw sync >/dev/null 2>&1 || true

echo ""
echo "✓ Done. Uploaded $n_uploaded key(s), skipped $n_skipped, into '$ITEM_NAME'."

if (( n_uploaded > 0 )); then
    echo ""
    echo "Verify on this machine:"
    echo "  chezmoi apply --include=scripts -v"
    if [[ "$SCOPE" == "profile" ]]; then
        echo ""
        echo "Other machines on profile=$profile will pick up the new key(s) on next 'bootstrap.sh update'."
    fi
fi
