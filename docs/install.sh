#!/bin/sh
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

set -e

# ── Capture initial state ──────────────────────────────────────────────────────
INITIAL_PWD=$(pwd)

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
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec </dev/tty
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
    info "Xcode CLT not found — triggering installer."
    info "A dialog will appear — click 'Install', then wait for it to finish."
    xcode-select --install 2>/dev/null || true
    info "Waiting for Xcode CLT installation to complete (this may take a few minutes)..."
    while ! xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    ok "Xcode CLT installed."
else
    ok "Xcode CLT already installed at $(xcode-select -p)."
fi

# ── Step 3: Homebrew ──────────────────────────────────────────────────────────
info "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    info "Homebrew not found — installing (non-interactive)..."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
    info "Existing repo found — pulling latest changes (--ff-only)..."
    git -C "$INSTALL_DIR" pull --ff-only
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
export INITIAL_PWD

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
