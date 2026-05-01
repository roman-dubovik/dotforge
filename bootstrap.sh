#!/usr/bin/env bash
# Mac dotfiles bootstrap.
# Usage: curl -fsSL https://raw.githubusercontent.com/romandubovik/dotforge/main/bootstrap.sh | bash

set -euo pipefail

REPO="romandubovik/dotforge"
REPO_BRANCH="main"

# ── Helpers ──
say() { printf "\n→ %s\n" "$*"; }
ok()  { printf "  ✓ %s\n" "$*"; }
err() { printf "  ✗ %s\n" "$*" >&2; exit 1; }

# ── Pre-flight ──
if [[ "$(uname)" != "Darwin" ]]; then
    err "This bootstrap is for macOS only."
fi

if [[ "$(uname -m)" != "arm64" && "$(uname -m)" != "x86_64" ]]; then
    err "Unsupported architecture: $(uname -m)"
fi

say "Bootstrapping Mac dotfiles ($REPO@$REPO_BRANCH)..."

# ── Xcode Command Line Tools ──
if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode CLT already installed"
else
    say "Installing Xcode Command Line Tools (GUI dialog will appear)..."
    xcode-select --install || true
    # Wait for installation to finish (user clicks Install in dialog)
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
        printf "."
    done
    printf "\n"
    ok "Xcode CLT installed"
fi

# ── Homebrew ──
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew already installed"
else
    say "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for this session (Apple Silicon and Intel)
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# ── Bootstrap dependencies ──
say "Installing bootstrap dependencies (chezmoi, bw, yq, gum)..."
for pkg in chezmoi bitwarden-cli yq gum; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
        ok "$pkg already installed"
    else
        brew install "$pkg"
        ok "Installed $pkg"
    fi
done

# ── Interactive prompts ──
say "Configure this machine"

DEFAULT_MACHINE_NAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
MACHINE_NAME="$(gum input --prompt "Machine name (human-friendly): " --value "$DEFAULT_MACHINE_NAME")"
[[ -z "$MACHINE_NAME" ]] && err "Machine name required"

PROFILE="$(gum choose --header "Profile:" personal work)"
[[ -z "$PROFILE" ]] && err "Profile required"

ok "Machine: $MACHINE_NAME, profile: $PROFILE"

# ── Bitwarden ──
say "Login to Bitwarden (master password required)"

# If already logged in, just unlock; otherwise login.
if bw status 2>/dev/null | grep -q '"status":"unauthenticated"'; then
    BW_SESSION="$(bw login --raw)"
else
    BW_SESSION="$(bw unlock --raw)"
fi
export BW_SESSION
[[ -z "$BW_SESSION" ]] && err "Bitwarden session is empty"

trap 'bw lock >/dev/null 2>&1 || true' EXIT
ok "Bitwarden unlocked"

# ── chezmoi init + apply ──
say "Cloning dotfiles repo and applying configuration..."

chezmoi init --apply "$REPO" \
    --branch "$REPO_BRANCH" \
    --promptString "machine_name=$MACHINE_NAME" \
    --promptChoice "profile=$PROFILE"

ok "chezmoi apply complete"
say "Done! Restart your shell to pick up new configuration."
