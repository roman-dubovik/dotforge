#!/usr/bin/env bash
# Convert a freshly-cloned dotforge repo into your own personal bootstrap.
# Walks you through every step with explanations and confirmations.
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
#   --reset-ssh           Replace example SSH IdentityFile with id_ed25519
#   --create-remote       Auto-create new public repo on GitHub and push
#   --no-commit           Make changes but don't commit them
#   --non-interactive     Skip narration + prompts (auto on no-TTY)
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

ORIG_GH_USER="roman-dubovik"
ORIG_REPO_NAME="dotforge"
ORIG_NAME="Roman Dubovik"
ORIG_EMAIL_PERSONAL="booroman@gmail.com"
ORIG_SSH_KEY="id_ed25519_github_booroman"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gh-user)         GH_USER="$2"; shift 2 ;;
        --name)            FULL_NAME="$2"; shift 2 ;;
        --email)           EMAIL="$2"; shift 2 ;;
        --repo)            NEW_REPO_NAME="$2"; shift 2 ;;
        --reset-ssh)       RESET_SSH=1; shift ;;
        --create-remote)   CREATE_REMOTE=1; shift ;;
        --no-commit)       NO_COMMIT=1; shift ;;
        --non-interactive) INTERACTIVE=0; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ ! -t 0 ]] && INTERACTIVE=0

# ── Pretty-print helpers ──

style_header() {
    if (( INTERACTIVE == 1 )) && command -v gum >/dev/null 2>&1; then
        gum style --foreground 212 --bold --margin "1 0" "$@"
    else
        printf "\n=== %s ===\n" "$*"
    fi
}

style_note() {
    if (( INTERACTIVE == 1 )) && command -v gum >/dev/null 2>&1; then
        gum style --foreground 245 "$@"
    else
        printf "%s\n" "$*"
    fi
}

style_ok()   { printf "  ✓ %s\n" "$*"; }
style_step() { printf "  → %s\n" "$*"; }
style_warn() { printf "  ! %s\n" "$*" >&2; }
style_err()  { printf "  ✗ %s\n" "$*" >&2; exit 1; }

ask_yes() {
    # Default-yes confirm. Falls through to true if non-interactive.
    local prompt="$1"
    if (( INTERACTIVE == 0 )); then return 0; fi
    gum confirm --default=Yes "$prompt"
}

ask_no() {
    local prompt="$1"
    if (( INTERACTIVE == 0 )); then return 1; fi
    gum confirm --default=No "$prompt"
}

prompt_for() {
    local label="$1" default="$2"
    if (( INTERACTIVE == 1 )) && command -v gum >/dev/null 2>&1; then
        gum input --prompt "$label: " --value "$default"
    else
        printf "%s" "$default"
    fi
}

# ── Step 0: Welcome + sanity ──

style_header "dotforge — fork personalizer"
style_note "This script turns a fresh clone of $ORIG_GH_USER/$ORIG_REPO_NAME into"
style_note "your own personal Mac bootstrap, under a GitHub account you control."
style_note ""
style_note "It will:"
style_note "  1. Sanity-check that you're inside a dotforge clone"
style_note "  2. Ask you for your GitHub username, name, email, repo name"
style_note "  3. Show every substitution and ask for permission before applying"
style_note "  4. Show the resulting git diff so you can review"
style_note "  5. Commit the personalization"
style_note "  6. Optionally create the new repo on GitHub and push"
echo ""

if (( INTERACTIVE == 1 )); then
    command -v gum >/dev/null 2>&1 || style_err "gum is required for the interactive flow (brew install gum)"
fi

style_header "Step 1/6: Sanity check"

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || style_err "Not a git repo: $REPO_ROOT"
style_ok "Inside a git repo: $REPO_ROOT"

if [[ ! -f "$REPO_ROOT/bootstrap.sh" ]] \
   || ! grep -q "$ORIG_GH_USER/$ORIG_REPO_NAME" "$REPO_ROOT/bootstrap.sh"; then
    style_err "This doesn't look like a dotforge clone (no '$ORIG_GH_USER/$ORIG_REPO_NAME' in bootstrap.sh)"
fi
style_ok "Found '$ORIG_GH_USER/$ORIG_REPO_NAME' references — looks legit."

dirty="$(git -C "$REPO_ROOT" status --porcelain | head -1)"
if [[ -n "$dirty" ]]; then
    style_warn "Working tree has uncommitted changes."
    if ! ask_yes "Continue anyway? (your changes will be staged into the personalize commit)"; then
        echo "Cancelled."; exit 0
    fi
else
    style_ok "Working tree is clean."
fi

# ── Step 2/6: Collect inputs ──

style_header "Step 2/6: Your details"

if [[ -z "$GH_USER" ]]; then
    style_note "Your GitHub username is the namespace where the new repo will live."
    style_note "Example: if your username is 'friend-foo', the repo will be"
    style_note "  https://github.com/friend-foo/<repo-name>."
    GH_USER="$(prompt_for "GitHub username" "")"
fi
[[ -z "$GH_USER" ]] && style_err "GitHub username is required."
[[ "$GH_USER" =~ ^[a-zA-Z0-9-]+$ ]] || style_err "Invalid GitHub username (letters, digits, hyphens only)."
style_ok "GitHub username: $GH_USER"

if [[ -z "$FULL_NAME" ]]; then
    style_note ""
    style_note "Your full name goes into:"
    style_note "  • chezmoi/dot_gitconfig.tmpl    → ~/.gitconfig user.name"
    style_note "  • LICENSE                        → 'Copyright (c) ... <name>'"
    default_name="$(git config user.name 2>/dev/null || echo '')"
    FULL_NAME="$(prompt_for "Full name" "$default_name")"
fi
[[ -z "$FULL_NAME" ]] && style_err "Full name is required."
style_ok "Full name: $FULL_NAME"

if [[ -z "$EMAIL" ]]; then
    style_note ""
    style_note "Your email goes into the personal profile's gitconfig template."
    style_note "(Work-profile email stays as the placeholder — you can edit it later.)"
    default_email="$(git config user.email 2>/dev/null || echo '')"
    EMAIL="$(prompt_for "Email (for profile=personal)" "$default_email")"
fi
[[ -z "$EMAIL" ]] && style_err "Email is required."
style_ok "Email: $EMAIL"

if (( INTERACTIVE == 1 )) && [[ "$NEW_REPO_NAME" == "dotforge" ]]; then
    style_note ""
    style_note "Repo name on GitHub. Default 'dotforge' is fine — keep it unless"
    style_note "you already have a repo by that name on your account."
    NEW_REPO_NAME="$(prompt_for "Repo name" "dotforge")"
fi
[[ -z "$NEW_REPO_NAME" ]] && style_err "Repo name is required."
style_ok "Repo name: $NEW_REPO_NAME"

if (( INTERACTIVE == 1 )) && (( RESET_SSH == 0 )); then
    style_note ""
    style_note "The SSH config template currently references"
    style_note "  IdentityFile ~/.ssh/$ORIG_SSH_KEY"
    style_note "as an example. You probably want to reset it to a generic"
    style_note "  IdentityFile ~/.ssh/id_ed25519"
    style_note "and add your own keys via 'bootstrap.sh add-key' later."
    if ask_yes "Reset the SSH IdentityFile path to a generic placeholder?"; then
        RESET_SSH=1
    fi
fi
if (( RESET_SSH == 1 )); then
    style_ok "Will replace SSH key reference: $ORIG_SSH_KEY → id_ed25519"
else
    style_note "Will keep '$ORIG_SSH_KEY' in the SSH template (you can edit later)."
fi

# ── Step 3/6: Show plan and confirm ──

style_header "Step 3/6: Substitution plan"

echo "  In these tracked files:"
echo "    bootstrap.sh, README.md, docs/usage.md,"
echo "    chezmoi/dot_gitconfig.tmpl, LICENSE"
if (( RESET_SSH == 1 )); then
    echo "    chezmoi/private_dot_ssh/config.tmpl"
fi
echo ""
echo "  Substitute:"
printf "    %-32s → %s\n" "$ORIG_GH_USER/$ORIG_REPO_NAME" "$GH_USER/$NEW_REPO_NAME"
printf "    %-32s → %s\n" "$ORIG_NAME" "$FULL_NAME"
printf "    %-32s → %s\n" "$ORIG_EMAIL_PERSONAL" "$EMAIL"
if (( RESET_SSH == 1 )); then
    printf "    %-32s → %s\n" "$ORIG_SSH_KEY" "id_ed25519"
fi
echo ""
echo "  Files NOT touched (you'll customize separately):"
echo "    Brewfile          (run 'sync' on your Mac to overwrite with your apps)"
echo "    chezmoi/private_dot_zshrc.tmpl  ('chezmoi re-add' after first apply)"
echo "    chezmoi/dot_claude/settings.json (delete or replace by hand)"
echo "    docs/superpowers/* (historical design docs — left intact)"
echo ""

if ! ask_yes "Apply these substitutions?"; then
    style_note "Cancelled. No changes made."
    exit 0
fi

# ── Step 4/6: Apply ──

style_header "Step 4/6: Applying substitutions"

declare -a TARGETS=(
    "bootstrap.sh"
    "README.md"
    "docs/usage.md"
    "chezmoi/dot_gitconfig.tmpl"
    "LICENSE"
)
if (( RESET_SSH == 1 )); then
    TARGETS+=("chezmoi/private_dot_ssh/config.tmpl")
fi

do_replace_in() {
    local file="$1" find="$2" replace="$3"
    [[ -f "$file" ]] || return 0
    sed -i '' "s|$(printf '%s' "$find" | sed 's/[]\/$*.^[]/\\&/g')|$(printf '%s' "$replace" | sed 's/[\/&]/\\&/g')|g" "$file"
}

for f in "${TARGETS[@]}"; do
    fp="$REPO_ROOT/$f"
    [[ -f "$fp" ]] || { style_warn "skip (not found): $f"; continue; }
    style_step "Editing $f"
    do_replace_in "$fp" "$ORIG_GH_USER/$ORIG_REPO_NAME" "$GH_USER/$NEW_REPO_NAME"
    do_replace_in "$fp" "$ORIG_NAME"            "$FULL_NAME"
    do_replace_in "$fp" "$ORIG_EMAIL_PERSONAL"  "$EMAIL"
    if (( RESET_SSH == 1 )); then
        do_replace_in "$fp" "$ORIG_SSH_KEY"     "id_ed25519"
    fi
done

style_ok "Substitutions applied to ${#TARGETS[@]} file(s)."

# ── Step 5/6: Review and commit ──

style_header "Step 5/6: Review and commit"

style_note "Diff stat (lines changed per file):"
git -C "$REPO_ROOT" --no-pager diff --stat

if (( INTERACTIVE == 1 )); then
    if ask_no "Show full diff in pager?"; then
        git -C "$REPO_ROOT" --no-pager diff | gum pager
    fi
fi

if (( NO_COMMIT == 1 )); then
    style_note ""
    style_note "Skipping commit (--no-commit). Review with 'git diff' and commit manually."
    exit 0
fi

if ! ask_yes "Commit these changes?"; then
    style_note ""
    style_note "Skipped commit. Run 'git diff' to review, 'git commit' when ready."
    exit 0
fi

git -C "$REPO_ROOT" config user.name  "$FULL_NAME"  >/dev/null 2>&1 || true
git -C "$REPO_ROOT" config user.email "$EMAIL"      >/dev/null 2>&1 || true

git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -m "chore: personalize fork for $GH_USER/$NEW_REPO_NAME"
style_ok "Committed."

# ── Step 6/6: Create remote and push ──

style_header "Step 6/6: Create the new GitHub repo and push"

if (( CREATE_REMOTE == 0 )) && (( INTERACTIVE == 1 )); then
    style_note "I can create the public repo on GitHub via 'gh repo create' and"
    style_note "push to it right now. This requires:"
    style_note "  • gh CLI installed (it is)"
    style_note "  • gh auth login completed for $GH_USER (or one with permissions"
    style_note "    to create repos in that namespace)"
    style_note ""
    style_note "Alternatively, you can skip this and push manually later."
    if ask_yes "Create $GH_USER/$NEW_REPO_NAME on GitHub and push now?"; then
        CREATE_REMOTE=1
    fi
fi

if (( CREATE_REMOTE == 1 )); then
    command -v gh >/dev/null 2>&1 || style_err "gh CLI is required for --create-remote."

    if ! gh auth status >/dev/null 2>&1; then
        style_warn "gh is not authenticated."
        style_note "Run 'gh auth login' first, then re-run this script with --create-remote,"
        style_note "or push manually later (commands at the end of this output)."
        exit 1
    fi

    actual_user="$(gh api user --jq .login 2>/dev/null || echo '?')"
    if [[ "$actual_user" != "$GH_USER" ]]; then
        style_warn "gh is logged in as '$actual_user', but you typed '$GH_USER'."
        if ! ask_yes "Proceed anyway? (the repo will be created under $GH_USER if your token has access)"; then
            style_note "Aborted. Run 'gh auth switch' or 'gh auth login' for $GH_USER first."
            exit 1
        fi
    fi

    git -C "$REPO_ROOT" remote remove origin 2>/dev/null || true

    style_step "Creating $GH_USER/$NEW_REPO_NAME and pushing..."
    gh repo create "$GH_USER/$NEW_REPO_NAME" --public \
        --source="$REPO_ROOT" --remote=origin --push \
        --description "Personal Mac bootstrap (forked from $ORIG_GH_USER/$ORIG_REPO_NAME)"

    style_ok "Repo created at https://github.com/$GH_USER/$NEW_REPO_NAME"
    echo ""
    style_header "All done — your bootstrap URL"
    cat <<EOM

  curl -fsSL https://raw.githubusercontent.com/$GH_USER/$NEW_REPO_NAME/main/bootstrap.sh | bash

  Save that URL — that's how you (or anyone) bootstraps a Mac with YOUR config.

  Recommended next steps on your Mac:
    1. cd $REPO_ROOT
    2. ./bootstrap.sh setup   (full bootstrap: dotfiles + Brewfile + SSH keys)
    3. After setup, ./bootstrap.sh sync to update Brewfile with your apps
EOM
else
    style_note ""
    style_note "When ready, push manually:"
    cat <<EOM

  cd $REPO_ROOT
  git remote remove origin 2>/dev/null
  gh repo create $GH_USER/$NEW_REPO_NAME --public \\
      --source=. --remote=origin --push

EOM
fi
