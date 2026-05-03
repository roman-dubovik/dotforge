#!/usr/bin/env bash
# Replay CLI globals captured by `scripts/scan-cli.sh --capture` into
# the user's package managers.
#
# The cli-globals.txt format is:
#   <source>:<package>
# where <source> is one of: npm, pnpm, cargo, go, pip.
# Lines starting with `#` are comments. Sources whose package manager
# isn't on PATH are skipped silently — install the manager first
# (oh-my-zsh, nvm, pnpm, etc. — see the manual-install comment block at
# the bottom of Brewfile) and re-run `chezmoi apply`.
#
# Idempotent: each install command is gated on a "is it already there"
# check. Network failures don't abort the run, just print a warning.

set -uo pipefail

SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
REPO_ROOT="${SOURCE_PATH%/chezmoi}"
GLOBALS_FILE="$REPO_ROOT/cli-globals.txt"

if [[ ! -f "$GLOBALS_FILE" ]]; then
    echo "  (no cli-globals.txt — skipping CLI-globals install)"
    exit 0
fi

# Source nvm if available (provides npm via the user's default node version).
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    nvm use default >/dev/null 2>&1 || true
fi

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
esac

n_installed=0
n_skipped=0
n_already=0
n_failed=0

while IFS= read -r line; do
    # Skip comments and empties
    case "$line" in
        \#*|"") continue ;;
    esac

    src="${line%%:*}"
    pkg="${line#*:}"
    [[ -z "$pkg" || "$src" == "$pkg" ]] && continue

    case "$src" in
        npm)
            if ! command -v npm >/dev/null 2>&1; then
                echo "  ⏭ npm not available — skipping $pkg (install nvm + node first)"
                n_skipped=$((n_skipped+1))
                continue
            fi
            if npm ls -g --depth=0 --parseable 2>/dev/null | grep -qE "/$pkg(@|\$)"; then
                n_already=$((n_already+1))
                continue
            fi
            echo "→ npm install -g $pkg"
            if npm install -g "$pkg" >/dev/null 2>&1; then
                n_installed=$((n_installed+1))
            else
                echo "  ⚠ npm install failed: $pkg"
                n_failed=$((n_failed+1))
            fi
            ;;
        pnpm)
            if ! command -v pnpm >/dev/null 2>&1; then
                echo "  ⏭ pnpm not available — skipping $pkg"
                n_skipped=$((n_skipped+1))
                continue
            fi
            if pnpm list -g --depth=0 --parseable 2>/dev/null | grep -qE "/$pkg(@|\$)"; then
                n_already=$((n_already+1))
                continue
            fi
            echo "→ pnpm add -g $pkg"
            if pnpm add -g "$pkg" >/dev/null 2>&1; then
                n_installed=$((n_installed+1))
            else
                echo "  ⚠ pnpm add failed: $pkg"
                n_failed=$((n_failed+1))
            fi
            ;;
        cargo)
            if ! command -v cargo >/dev/null 2>&1; then
                echo "  ⏭ cargo not available — skipping $pkg"
                n_skipped=$((n_skipped+1))
                continue
            fi
            if cargo install --list 2>/dev/null | grep -qE "^${pkg} "; then
                n_already=$((n_already+1))
                continue
            fi
            echo "→ cargo install $pkg"
            if cargo install "$pkg" >/dev/null 2>&1; then
                n_installed=$((n_installed+1))
            else
                echo "  ⚠ cargo install failed: $pkg"
                n_failed=$((n_failed+1))
            fi
            ;;
        go)
            # Go install needs a full module path, not just the binary
            # name. We can't reliably reconstruct that from the bin name
            # alone, so we just inform the user.
            echo "  ℹ go binary tracked but not auto-installed: $pkg"
            echo "    install it manually with 'go install <module>@latest'"
            n_skipped=$((n_skipped+1))
            ;;
        pip)
            if ! command -v pip3 >/dev/null 2>&1; then
                echo "  ⏭ pip3 not available — skipping $pkg"
                n_skipped=$((n_skipped+1))
                continue
            fi
            if pip3 list --user --format=freeze 2>/dev/null | grep -qE "^${pkg}=="; then
                n_already=$((n_already+1))
                continue
            fi
            echo "→ pip3 install --user $pkg"
            if pip3 install --user "$pkg" >/dev/null 2>&1; then
                n_installed=$((n_installed+1))
            else
                echo "  ⚠ pip3 install failed: $pkg"
                n_failed=$((n_failed+1))
            fi
            ;;
        *)
            echo "  ⚠ unknown source '$src' (line: $line)"
            ;;
    esac
done < "$GLOBALS_FILE"

echo ""
echo "✓ CLI globals: $n_installed installed, $n_already already present, $n_skipped skipped, $n_failed failed"
