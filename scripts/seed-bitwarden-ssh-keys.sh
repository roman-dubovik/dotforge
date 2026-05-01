#!/usr/bin/env bash
# Create or update the `dotforge-ssh-<profile>` Bitwarden item and upload
# all SSH key attachments (private + .pub for each basename) from ~/.ssh/.
#
# Usage:
#   bw login                                # if not already authenticated
#   export BW_SESSION="$(bw unlock --raw)"  # unlock vault
#   ./scripts/seed-bitwarden-ssh-keys.sh personal
#
# Requires: bw, jq.
# Idempotent at the item level (reuses an existing item with the same name);
# attachments are appended, so delete stale ones via the Bitwarden GUI before
# re-running with rotated keys.

set -euo pipefail

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
    echo "Usage: $0 <profile>   (e.g. personal, work)" >&2
    exit 1
fi

if [[ -z "${BW_SESSION:-}" ]]; then
    echo "BW_SESSION is not set." >&2
    echo "Run:  export BW_SESSION=\"\$(bw unlock --raw)\"" >&2
    exit 1
fi

for cmd in bw jq; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

ITEM_NAME="dotforge-ssh-$PROFILE"
SSH_DIR="$HOME/.ssh"

# Profile-specific key list (kept in sync with
# chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl).
case "$PROFILE" in
    personal)
        KEY_BASENAMES=(
            id_ed25519_github_booroman
            id_ed25519
            id_ed25519_ident_tg_bot
            id_rsa
            id_rsa_pureboard
        )
        ;;
    work)
        KEY_BASENAMES=(
            id_ed25519_work
        )
        ;;
    *)
        echo "Unknown profile: $PROFILE" >&2
        exit 1
        ;;
esac

# Verify all source files exist before creating any Bitwarden state.
missing=()
for basename in "${KEY_BASENAMES[@]}"; do
    [[ -f "$SSH_DIR/$basename"     ]] || missing+=("$basename")
    [[ -f "$SSH_DIR/$basename.pub" ]] || missing+=("$basename.pub")
done
if (( ${#missing[@]} > 0 )); then
    printf "Missing SSH key files in %s:\n" "$SSH_DIR" >&2
    printf "  - %s\n" "${missing[@]}" >&2
    exit 1
fi

bw sync >/dev/null

# Find existing item, or create a new login-type item.
ITEM_ID="$(bw list items --search "$ITEM_NAME" 2>/dev/null \
    | jq -r --arg n "$ITEM_NAME" '.[] | select(.name == $n) | .id' \
    | head -n 1)"

if [[ -z "$ITEM_ID" ]]; then
    echo "Creating Bitwarden item '$ITEM_NAME'..."
    # Type 2 = Secure Note (no login fields needed for an attachment-only item).
    # The .login={uris:[]} stub avoids a known bw bug that reads .login.uris
    # even when type != 1.
    ITEM_ID="$(bw get template item \
        | jq --arg name "$ITEM_NAME" --arg notes "Managed by dotforge. SSH keys for profile $PROFILE" \
            '.type = 2 | .name = $name | .notes = $notes
             | .secureNote = {"type": 0}
             | .login = {"uris": [], "username": null, "password": null, "totp": null}' \
        | bw encode \
        | bw create item \
        | jq -r '.id')"
    echo "  ✓ Created item $ITEM_ID"
else
    echo "Reusing existing item '$ITEM_NAME' ($ITEM_ID)"
fi

for basename in "${KEY_BASENAMES[@]}"; do
    for suffix in "" ".pub"; do
        file="$SSH_DIR/$basename$suffix"
        echo "  → Uploading $basename$suffix"
        bw create attachment --itemid "$ITEM_ID" --file "$file" >/dev/null
    done
done

bw sync >/dev/null
echo "✓ Done. ${#KEY_BASENAMES[@]} key pair(s) uploaded to '$ITEM_NAME'."
