#!/usr/bin/env bash
# Add an SSH key to Bitwarden so the chezmoi hook can restore it on this
# (or other) machine(s).
#
# Two scopes:
#   profile  — uploaded to dotforge-ssh-<profile>; every machine using
#              this profile will fetch it on the next chezmoi apply
#   machine  — uploaded to dotforge-ssh-<profile>-<machine_name>;
#              ONLY this machine will fetch it
#
# Usage:
#   add-ssh-key.sh <basename>       # interactive scope picker
#   add-ssh-key.sh <basename> --scope profile
#   add-ssh-key.sh <basename> --scope machine
#   add-ssh-key.sh                  # picks one of ~/.ssh/id_* interactively
#
# Requires: bw (unlocked, BW_SESSION exported), jq.

set -euo pipefail

BASENAME=""
SCOPE=""
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope) SCOPE="$2"; shift 2 ;;
        --non-interactive) INTERACTIVE=0; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$BASENAME" ]]; then
                BASENAME="$1"
            else
                echo "Unexpected argument: $1" >&2; exit 2
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

# Read profile + machine_name from chezmoi config
CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
[[ -f "$CONFIG" ]] || { echo "$CONFIG not found (run 'chezmoi init' first)" >&2; exit 1; }

profile="$(grep -E '^[[:space:]]*profile[[:space:]]*=' "$CONFIG" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
machine="$(grep -E '^[[:space:]]*machine_name[[:space:]]*=' "$CONFIG" | head -1 | sed 's/.*"\(.*\)".*/\1/')"

[[ -z "$profile" ]] && { echo "profile missing in $CONFIG" >&2; exit 1; }
[[ -z "$machine" ]] && { echo "machine_name missing in $CONFIG" >&2; exit 1; }

# Pick a basename if not given
if [[ -z "$BASENAME" ]]; then
    if (( INTERACTIVE == 0 )); then
        echo "Need a key basename in non-interactive mode (positional arg)." >&2
        exit 2
    fi
    command -v gum >/dev/null 2>&1 || { echo "gum is required for the picker" >&2; exit 1; }
    candidates=()
    while IFS= read -r f; do
        [[ -f "$f.pub" ]] && candidates+=("$(basename "$f")")
    done < <(find "$HOME/.ssh" -maxdepth 1 -name "id_*" -not -name "*.pub" 2>/dev/null | sort)
    if (( ${#candidates[@]} == 0 )); then
        echo "No key pairs found in ~/.ssh/" >&2
        exit 1
    fi
    BASENAME="$(printf "%s\n" "${candidates[@]}" | gum choose --header "Pick a key to upload:")"
    [[ -z "$BASENAME" ]] && { echo "Cancelled."; exit 1; }
fi

PRIV="$HOME/.ssh/$BASENAME"
PUB="$PRIV.pub"
[[ -f "$PRIV" ]] || { echo "Missing $PRIV" >&2; exit 1; }
[[ -f "$PUB" ]]  || { echo "Missing $PUB" >&2; exit 1; }

# Show key info
fingerprint="$(ssh-keygen -lf "$PUB" 2>/dev/null | awk '{print $2}' || echo '?')"
echo "Key:         $BASENAME"
echo "Fingerprint: $fingerprint"
echo "Profile:     $profile"
echo "Machine:     $machine"
echo ""

# Pick scope
if [[ -z "$SCOPE" ]]; then
    if (( INTERACTIVE == 0 )); then
        echo "--scope required in non-interactive mode (profile|machine)" >&2
        exit 2
    fi
    command -v gum >/dev/null 2>&1 || { echo "gum is required for the scope picker" >&2; exit 1; }
    pick="$(gum choose --header "Where to store '$BASENAME'?" \
        "profile  — shared with all machines using profile=$profile" \
        "machine  — only on $machine (other machines won't get it)")"
    [[ -z "$pick" ]] && { echo "Cancelled."; exit 1; }
    SCOPE="${pick%% *}"
fi

case "$SCOPE" in
    profile) ITEM_NAME="dotforge-ssh-$profile" ;;
    machine) ITEM_NAME="dotforge-ssh-$profile-$machine" ;;
    *) echo "Invalid scope: $SCOPE (expected: profile|machine)" >&2; exit 1 ;;
esac

bw sync >/dev/null

# Find or create the item
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
else
    # If a key with this basename already exists in the item, ask before
    # appending a duplicate attachment.
    existing="$(bw get item "$ITEM_ID" \
        | jq -r --arg n "$BASENAME" '.attachments[]? | select(.fileName == $n) | .id' \
        | head -1)"
    if [[ -n "$existing" ]]; then
        echo "Key '$BASENAME' already exists as an attachment in '$ITEM_NAME'."
        if (( INTERACTIVE == 1 )) && command -v gum >/dev/null 2>&1; then
            if ! gum confirm --default=No "Append a duplicate attachment? (You may want to delete the old one in the GUI first.)"; then
                echo "Cancelled."
                exit 0
            fi
        else
            echo "  Use Bitwarden GUI to delete the old attachment, then re-run." >&2
            exit 1
        fi
    fi
fi

echo "→ Uploading $BASENAME"
bw create attachment --itemid "$ITEM_ID" --file "$PRIV" >/dev/null
echo "→ Uploading $BASENAME.pub"
bw create attachment --itemid "$ITEM_ID" --file "$PUB" >/dev/null
bw sync >/dev/null

echo ""
echo "✓ Uploaded '$BASENAME' (private + .pub) to Bitwarden item '$ITEM_NAME'"
echo ""
echo "Next steps:"
echo "  • This machine: 'chezmoi apply --include=scripts -v' to verify the hook"
echo "    can fetch the new key (no-op if already present on disk)."
if [[ "$SCOPE" == "profile" ]]; then
    echo "  • Other machines on profile=$profile: next 'chezmoi update' will pick"
    echo "    up the new key automatically (hook enumerates attachments)."
else
    echo "  • Other machines: nothing — this key is scoped to $machine only."
fi
