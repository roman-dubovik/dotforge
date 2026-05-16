#!/usr/bin/env bash
# Install curl-based toolchains that have no Homebrew formula.
#
# Order matters: oh-my-zsh first (p10k/plugins clone into its custom dir),
# then nvm (provides npm for run_onchange_30-install-cli-globals.sh).
#
# Idempotent: every item is skipped if already present.
# DRY_RUN=1: print "would: <action>" for each item, exit 0, no network calls.
#
# Exit policy: individual failures are warned but do NOT abort the run —
# a single broken installer must not block the rest of chezmoi apply.

set -uo pipefail

SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
REPO_ROOT="${SOURCE_PATH%/chezmoi}"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---------------------------------------------------------------------------
# 1. oh-my-zsh
# ---------------------------------------------------------------------------
install_omz() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: install oh-my-zsh via curl | sh --unattended --keep-zshrc"
        return 0
    fi
    if [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
        log_ok "oh-my-zsh already installed"
        return 0
    fi
    log_info "Installing oh-my-zsh..."
    if RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended --keep-zshrc; then
        log_ok "oh-my-zsh installed"
    else
        log_warn "oh-my-zsh install failed (exit $?) — continuing"
    fi
}

# ---------------------------------------------------------------------------
# 2. powerlevel10k theme
# ---------------------------------------------------------------------------
install_p10k() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: git clone --depth=1 powerlevel10k into \$ZSH_CUSTOM/themes/powerlevel10k"
        return 0
    fi
    local dest="$ZSH_CUSTOM/themes/powerlevel10k"
    if [[ -d "$dest" ]]; then
        log_ok "powerlevel10k already installed"
        return 0
    fi
    log_info "Installing powerlevel10k..."
    if git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$dest" 2>&1; then
        log_ok "powerlevel10k installed"
    else
        log_warn "powerlevel10k clone failed — continuing"
    fi
}

# ---------------------------------------------------------------------------
# 3. zsh custom plugins (syntax-highlighting, autosuggestions, completions)
# ---------------------------------------------------------------------------
install_zsh_plugins() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: git clone --depth=1 zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions into \$ZSH_CUSTOM/plugins/"
        return 0
    fi

    declare -A plugins=(
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions.git"
        [zsh-completions]="https://github.com/zsh-users/zsh-completions.git"
    )

    for name in zsh-syntax-highlighting zsh-autosuggestions zsh-completions; do
        local dest="$ZSH_CUSTOM/plugins/$name"
        if [[ -d "$dest" ]]; then
            log_ok "$name already installed"
            continue
        fi
        log_info "Installing $name..."
        if git clone --depth=1 "${plugins[$name]}" "$dest" 2>&1; then
            log_ok "$name installed"
        else
            log_warn "$name clone failed — continuing"
        fi
    done
}

# ---------------------------------------------------------------------------
# 4. nvm + LTS Node
# ---------------------------------------------------------------------------
install_nvm() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: install nvm v0.40.0 via curl | bash, then nvm install --lts"
        return 0
    fi
    export NVM_DIR="$HOME/.nvm"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        log_ok "nvm already installed"
        return 0
    fi
    log_info "Installing nvm..."
    if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash; then
        log_ok "nvm installed"
        # Source nvm and install LTS so run_onchange_30-install-cli-globals finds npm.
        # set +u: nvm.sh references unset vars internally; guard around the source.
        set +u
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        set -u
        log_info "Installing Node LTS via nvm..."
        if nvm install --lts; then
            log_ok "Node LTS installed"
        else
            log_warn "nvm install --lts failed — continuing"
        fi
    else
        log_warn "nvm install failed — continuing"
    fi
}

# ---------------------------------------------------------------------------
# 5. pnpm
# ---------------------------------------------------------------------------
install_pnpm() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: install pnpm via curl -fsSL https://get.pnpm.io/install.sh | sh -"
        return 0
    fi
    if [[ -x "$HOME/.local/share/pnpm/pnpm" || -x "$HOME/Library/pnpm/pnpm" ]]; then
        log_ok "pnpm already installed"
        return 0
    fi
    log_info "Installing pnpm..."
    if curl -fsSL https://get.pnpm.io/install.sh | sh -; then
        log_ok "pnpm installed"
    else
        log_warn "pnpm install failed — continuing"
    fi
}

# ---------------------------------------------------------------------------
# 6. maestro
# ---------------------------------------------------------------------------
install_maestro() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "would: install maestro via curl -Ls https://get.maestro.mobile.dev | bash"
        return 0
    fi
    if [[ -x "$HOME/.maestro/bin/maestro" ]]; then
        log_ok "maestro already installed"
        return 0
    fi
    log_info "Installing maestro..."
    if curl -Ls "https://get.maestro.mobile.dev" | bash; then
        log_ok "maestro installed"
    else
        log_warn "maestro install failed — continuing"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log_section "Curl-based toolchains"

install_omz
install_p10k
install_zsh_plugins
install_nvm
install_pnpm
install_maestro

log_ok "curl-toolchains hook complete"
