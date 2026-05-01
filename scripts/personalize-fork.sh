#!/usr/bin/env bash
# Convert a freshly-cloned dotforge repo into your own personal bootstrap.
# Replaces all hardcoded references to the original author with values you
# provide, then (optionally) creates a new GitHub repo under your account
# and pushes.
#
# Run inside the cloned repo:
#   git clone https://github.com/roman-dubovik/dotforge mybootstrap
#   cd mybootstrap
#   ./scripts/personalize-fork.sh
#
# Non-interactive form (skip prompts):
#   ./scripts/personalize-fork.sh \
#       --gh-user friend-foo \
#       --name "Friend Foo" \
#       --email friend@example.com \
#       --repo dotforge \
#       --create-remote
#
# Flags:
#   --gh-user <login>     GitHub username for the new repo
#   --name "..."          Full name (goes into git author + LICENSE)
#   --email <email>       Email for git author / personal profile
#   --repo <name>         Repo name on GitHub (default: dotforge)
#   --reset-ssh           Replace the example SSH IdentityFile path with
#                         a generic id_ed25519 placeholder
#   --create-remote       After commit, create a new public repo on GitHub
#                         and push (requires `gh` authenticated)
#   --no-commit           Make changes but don't commit them
#   --non-interactive     Skip all gum prompts (auto on no-TTY)
#   --help|-h             Show this header

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GH_USER=""
FULL_NAME=""
EMAIL=""
NEW_REPO_NAME="dotforge"
RESET_SSH=0
CREATE_REMOTE=0
NO_COMMIT=0
INTERACTIVE=1

# Original repo coordinates (the only place these magic strings live)
ORIG_GH_USER="roman-dubovik"
ORIG_REPO_NAME="dotforge"
ORIG_NAME="Roman Dubovik"
ORIG_EMAIL_PERSONAL="booroman@gmail.com"
ORIG_SSH_KEY="id_ed25519_github_booroman"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gh-user)         GH_USER="$2"; shift 2 ;;
        --name)             FULL_NAME="$2"; shift 2 ;;
        --email)            EMAIL="$2"; shift 2 ;;
        --repo)             NEW_REPO_NAME="$2"; shift 2 ;;
        --reset-ssh)        RESET_SSH=1; shift ;;
        --create-remote)    CREATE_REMOTE=1; shift ;;
        --no-commit)        NO_COMMIT=1; shift ;;
        --non-interactive)  INTERACTIVE=0; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ ! -t 0 ]] && INTERACTIVE=0

# ── Sanity checks ──

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "Not a git repo: $REPO_ROOT" >&2; exit 1; }

if [[ ! -f "$REPO_ROOT/bootstrap.sh" ]] || ! grep -q "$ORIG_GH_USER/$ORIG_REPO_NAME" "$REPO_ROOT/bootstrap.sh"; then
    echo "This doesn't look like a dotforge clone." >&2
    echo "Expected '$ORIG_GH_USER/$ORIG_REPO_NAME' references in bootstrap.sh." >&2
    exit 1
fi

if (( INTERACTIVE == 1 )); then
    command -v gum >/dev/null 2>&1 || { echo "gum is required for prompts" >&2; exit 1; }
fi

# ── Collect inputs ──

prompt_input() {
    local var_label="$1" default="$2"
    if (( INTERACTIVE == 1 )); then
        gum input --prompt "$var_label: " --value "$default"
    else
        printf "%s" "$default"
    fi
}

if [[ -z "$GH_USER" ]]; then
    GH_USER="$(prompt_input "GitHub username (where the new repo will live)" "")"
fi
[[ -z "$GH_USER" ]] && { echo "GitHub username required" >&2; exit 1; }
[[ "$GH_USER" =~ ^[a-zA-Z0-9-]+$ ]] || { echo "Invalid GitHub username" >&2; exit 1; }

if [[ -z "$FULL_NAME" ]]; then
    default_name="$(git config user.name 2>/dev/null || echo '')"
    FULL_NAME="$(prompt_input "Full name (for git author + LICENSE)" "$default_name")"
fi
[[ -z "$FULL_NAME" ]] && { echo "Full name required" >&2; exit 1; }

if [[ -z "$EMAIL" ]]; then
    default_email="$(git config user.email 2>/dev/null || echo '')"
    EMAIL="$(prompt_input "Email (used for profile=personal)" "$default_email")"
fi
[[ -z "$EMAIL" ]] && { echo "Email required" >&2; exit 1; }

if [[ "$NEW_REPO_NAME" == "dotforge" ]] && (( INTERACTIVE == 1 )); then
    NEW_REPO_NAME="$(prompt_input "Repo name on GitHub" "dotforge")"
fi
[[ -z "$NEW_REPO_NAME" ]] && { echo "Repo name required" >&2; exit 1; }

# ── Show plan ──

cat <<INFO

About to personalize this clone:

  Original              →  Yours
  ────────────────────────────────────────────
  $ORIG_GH_USER/$ORIG_REPO_NAME    →  $GH_USER/$NEW_REPO_NAME
  $ORIG_NAME            →  $FULL_NAME
  $ORIG_EMAIL_PERSONAL  →  $EMAIL
INFO
if (( RESET_SSH == 1 )); then
    cat <<INFO
  $ORIG_SSH_KEY (in ssh config)
                        →  id_ed25519 (generic placeholder)
INFO
fi
echo ""

if (( INTERACTIVE == 1 )) && ! gum confirm --default=Yes "Proceed with these substitutions?"; then
    echo "Cancelled."
    exit 0
fi

# ── Find / replace ──

# Limit edits to tracked files we know about. Don't touch design docs in
# docs/superpowers/* (they're historical references, fine to leave).
declare -a TARGETS=(
    "bootstrap.sh"
    "README.md"
    "docs/usage.md"
    "chezmoi/dot_gitconfig.tmpl"
    "LICENSE"
)

# Some substitutions need a leading-anchor regex (e.g., the SSH key name
# only inside the SSH template). Most are global token swaps.
do_replace_in() {
    local file="$1" find="$2" replace="$3"
    [[ -f "$file" ]] || return 0
    # macOS BSD sed: -i '' for in-place
    sed -i '' "s|$(printf '%s' "$find" | sed 's/[]\/$*.^[]/\\&/g')|$(printf '%s' "$replace" | sed 's/[\/&]/\\&/g')|g" "$file"
}

for f in "${TARGETS[@]}"; do
    fp="$REPO_ROOT/$f"
    [[ -f "$fp" ]] || continue
    do_replace_in "$fp" "$ORIG_GH_USER/$ORIG_REPO_NAME" "$GH_USER/$NEW_REPO_NAME"
    do_replace_in "$fp" "$ORIG_NAME" "$FULL_NAME"
    do_replace_in "$fp" "$ORIG_EMAIL_PERSONAL" "$EMAIL"
done

# bootstrap.sh's REPO_URL/RAW_URL derive from REPO. Earlier replace handled
# the path; the URL is composed at runtime, so no extra work.

# Optional SSH key reset
if (( RESET_SSH == 1 )); then
    SSH_TMPL="$REPO_ROOT/chezmoi/private_dot_ssh/config.tmpl"
    if [[ -f "$SSH_TMPL" ]]; then
        do_replace_in "$SSH_TMPL" "$ORIG_SSH_KEY" "id_ed25519"
    fi
fi

echo "→ Showing diff:"
git -C "$REPO_ROOT" --no-pager diff --stat

if (( INTERACTIVE == 1 )); then
    if gum confirm --default=No "Show full diff?"; then
        git -C "$REPO_ROOT" --no-pager diff | gum pager
    fi
fi

# ── Commit ──

if (( NO_COMMIT == 1 )); then
    echo "Skipped commit (--no-commit). Review with 'git diff' and commit by hand."
    exit 0
fi

git -C "$REPO_ROOT" config user.name  "$FULL_NAME"  >/dev/null 2>&1 || true
git -C "$REPO_ROOT" config user.email "$EMAIL"      >/dev/null 2>&1 || true

git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -m "chore: personalize fork for $GH_USER/$NEW_REPO_NAME"

echo "✓ Committed personalization changes."

# ── Optional: create remote and push ──

if (( CREATE_REMOTE == 0 )) && (( INTERACTIVE == 1 )); then
    if gum confirm --default=Yes "Create new public repo $GH_USER/$NEW_REPO_NAME on GitHub and push?"; then
        CREATE_REMOTE=1
    fi
fi

if (( CREATE_REMOTE == 1 )); then
    command -v gh >/dev/null 2>&1 || { echo "gh CLI is required for --create-remote" >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated. Run 'gh auth login' first." >&2; exit 1; }

    # Replace origin so push goes to the user's account, not roman-dubovik.
    git -C "$REPO_ROOT" remote remove origin 2>/dev/null || true

    gh repo create "$GH_USER/$NEW_REPO_NAME" --public \
        --source="$REPO_ROOT" --remote=origin --push \
        --description "Personal Mac bootstrap (forked from roman-dubovik/dotforge)"

    echo ""
    echo "✓ Repo created at https://github.com/$GH_USER/$NEW_REPO_NAME"
    echo ""
    echo "Your bootstrap URL is now:"
    echo "  curl -fsSL https://raw.githubusercontent.com/$GH_USER/$NEW_REPO_NAME/main/bootstrap.sh | bash"
else
    echo ""
    echo "When ready, push manually:"
    echo "  git -C $REPO_ROOT remote remove origin"
    echo "  gh repo create $GH_USER/$NEW_REPO_NAME --public --source=$REPO_ROOT --remote=origin --push"
fi
