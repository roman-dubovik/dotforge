#!/usr/bin/env bash
# dotforge curl-installer — bootstrap a fresh Mac end-to-end.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/docs/install.sh | bash
#
# Env-var overrides (set before piping):
#   DOTFORGE_REPO_URL        default: https://github.com/roman-dubovik/dotforge.git
#   DOTFORGE_BRANCH          default: main
#   DOTFORGE_INSTALL_DIR     default: $HOME/dotforge
#   DOTFORGE_MACHINE_NAME    forwarded to bootstrap.sh setup
#   DOTFORGE_PROFILE         forwarded to bootstrap.sh setup
#   DOTFORGE_BREWFILE_ARCHETYPE  forwarded to bootstrap.sh setup

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DOTFORGE_REPO_URL="${DOTFORGE_REPO_URL:-https://github.com/roman-dubovik/dotforge.git}"
DOTFORGE_BRANCH="${DOTFORGE_BRANCH:-main}"
DOTFORGE_INSTALL_DIR="${DOTFORGE_INSTALL_DIR:-$HOME/dotforge}"

# ── Helpers ───────────────────────────────────────────────────────────────────
info() { printf "dotforge install: → %s\n" "$*"; }
ok()   { printf "dotforge install: ✓ %s\n" "$*"; }
err()  { printf "dotforge install: ✗ %s\n" "$*" >&2; exit 1; }

# ── TTY re-open (curl | bash trick) ──────────────────────────────────────────
# When piped from curl, stdin is not a TTY. Re-open /dev/tty so that
# Xcode CLT prompts, brew, and bootstrap.sh can request interactive input.
if [ ! -t 0 ]; then
    if [ -r /dev/tty ]; then
        exec </dev/tty
    else
        err "Non-interactive environment without /dev/tty. Re-run from a terminal, or pre-set DOTFORGE_MACHINE_NAME / DOTFORGE_PROFILE / DOTFORGE_BREWFILE_ARCHETYPE env vars before piping to bash."
    fi
fi

# ── Step 1: Verify macOS ──────────────────────────────────────────────────────
info "Checking platform..."
if [ "$(uname)" != "Darwin" ]; then
    err "dotforge is macOS-only (this system reports: $(uname))."
fi
ok "macOS $(sw_vers -productVersion) detected."

# ── Step 2: Xcode Command Line Tools ─────────────────────────────────────────
info "Checking Xcode Command Line Tools..."
if ! xcode-select -p >/dev/null 2>&1; then
    info "Triggering Xcode Command Line Tools install (dialog will appear)"
    xcode-select --install || true   # stderr passes through; non-zero is normal when already queued
    info "Waiting for Xcode CLT (up to ~6 min; press Ctrl-C to abort)"
    attempt=0
    while ! xcode-select -p >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 72 ]; then
            err "Timed out after 6 min waiting for Xcode CLT. Install manually: 'xcode-select --install', then re-run this installer."
        fi
        sleep 5
    done
    ok "Xcode Command Line Tools ready"
else
    ok "Xcode CLT already installed at $(xcode-select -p)."
fi

# ── Step 3: Homebrew ──────────────────────────────────────────────────────────
info "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    info "Homebrew not found — installing (non-interactive)..."
    _brew_installer=$(mktemp -t dotforge-brew-install.XXXXXX)
    trap 'rm -f "$_brew_installer"' EXIT
    _curl_rc=0
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$_brew_installer" || _curl_rc=$?
    if [ "$_curl_rc" -ne 0 ]; then
        err "Failed to download Homebrew installer (curl exit $_curl_rc). Check network/proxy and retry."
    fi
    NONINTERACTIVE=1 /bin/bash "$_brew_installer"
    rm -f "$_brew_installer"
    trap - EXIT

    # After curl-install, brew is not yet on PATH — source shellenv.
    if [ -x "/opt/homebrew/bin/brew" ]; then
        # Apple Silicon
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        # Intel
        eval "$(/usr/local/bin/brew shellenv)"
    else
        err "Homebrew was installed but 'brew' binary not found at expected paths."
    fi
    ok "Homebrew installed."
else
    ok "Homebrew already installed at $(command -v brew)."
fi

# ── Step 4: git ───────────────────────────────────────────────────────────────
info "Checking git..."
if ! command -v git >/dev/null 2>&1; then
    info "git not found — installing via brew..."
    brew install git
    ok "git installed."
else
    ok "git already available: $(git --version)."
fi

# ── Step 5: Clone or update dotforge repo ────────────────────────────────────
INSTALL_DIR="$DOTFORGE_INSTALL_DIR"
info "Checking dotforge repo at $INSTALL_DIR..."

if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing dotforge checkout at $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch origin
    current_branch=$(git -C "$INSTALL_DIR" branch --show-current)
    if [ "$current_branch" != "$DOTFORGE_BRANCH" ]; then
        info "Switching from '$current_branch' to '$DOTFORGE_BRANCH'"
        git -C "$INSTALL_DIR" checkout "$DOTFORGE_BRANCH"
    fi
    if ! git -C "$INSTALL_DIR" pull --ff-only; then
        err "Failed to fast-forward '$INSTALL_DIR' (diverged?). Run: cd $INSTALL_DIR && git status"
    fi
    ok "Repository updated."
elif [ -d "$INSTALL_DIR" ]; then
    err "Directory '$INSTALL_DIR' exists but is not a git repository. Please remove it or set DOTFORGE_INSTALL_DIR to a different path."
else
    info "Cloning $DOTFORGE_REPO_URL (branch: $DOTFORGE_BRANCH)..."
    git clone --branch "$DOTFORGE_BRANCH" "$DOTFORGE_REPO_URL" "$INSTALL_DIR"
    ok "Repository cloned to $INSTALL_DIR."
fi

# ── Step 6: Exec bootstrap.sh setup ──────────────────────────────────────────
# Export env-vars so bootstrap.sh and its sub-processes can see them.
export DOTFORGE_REPO_URL
export DOTFORGE_BRANCH
export DOTFORGE_INSTALL_DIR

# Optional forwarded vars — only export if non-empty.
if [ -n "${DOTFORGE_MACHINE_NAME:-}" ]; then
    export DOTFORGE_MACHINE_NAME
fi
if [ -n "${DOTFORGE_PROFILE:-}" ]; then
    export DOTFORGE_PROFILE
fi
if [ -n "${DOTFORGE_BREWFILE_ARCHETYPE:-}" ]; then
    export DOTFORGE_BREWFILE_ARCHETYPE
fi

info "Handing off to bootstrap.sh setup..."
exec bash "$INSTALL_DIR/bootstrap.sh" setup "$@"
