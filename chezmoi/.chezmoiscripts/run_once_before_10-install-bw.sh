#!/usr/bin/env bash
# Ensure Bitwarden CLI, yq, and jq are installed.
# Idempotent: skips if already present.

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed. Run bootstrap.sh first." >&2
    exit 1
fi

for pkg in bitwarden-cli yq jq; do
    if ! brew list --formula "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        brew install "$pkg"
    fi
done
