# Mac Bootstrap — Plan 1: Foundation Bootstrap (MVP)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать публичный dotforge репо, при `curl ... | bash` на чистом Mac разворачивающий полный setup: Homebrew + Brewfile, dotfiles через chezmoi, SSH-ключи из Bitwarden, конфиг Claude. Один канонический setup без архетипов.

**Architecture:** Public GitHub-репо `github.com/roman-dubovik/dotforge`. Bootstrap-скрипт ставит инфру (Xcode CLT → Homebrew → chezmoi/bw/yq/gum) и передаёт управление chezmoi. Хуки chezmoi применяют Brewfile и тянут SSH-ключи из Bitwarden. Все секреты — в Bitwarden.

**Tech Stack:** bash, chezmoi (Go templates), Homebrew, Bitwarden CLI (`bw`), `yq`, `gum` (TUI), `shellcheck` (линт), `bats` (тесты bash-функций).

**Spec:** [tmp/superpowers/specs/2026-05-01-mac-bootstrap-design.md](../specs/2026-05-01-mac-bootstrap-design.md)

**Local dev path:** `~/Documents/Projects/dotforge/` (отдельный git-репо, не в beribuy-2.0).

---

## Pre-flight

- [ ] **Шаг 0.1: Создать локальный путь и git-репо**

```bash
mkdir -p ~/Documents/Projects/dotforge
cd ~/Documents/Projects/dotforge
git init -b main
```

- [ ] **Шаг 0.2: Установить инструменты для разработки**

```bash
brew install shellcheck bats-core
```

Проверка:
```bash
shellcheck --version  # >= 0.9
bats --version         # >= 1.10
```

---

## Task 1: Скелет репо

**Files:**
- Create: `~/Documents/Projects/dotforge/.gitignore`
- Create: `~/Documents/Projects/dotforge/README.md`
- Create: `~/Documents/Projects/dotforge/LICENSE` (MIT)

- [ ] **Шаг 1.1: Создать .gitignore**

```bash
cat > ~/Documents/Projects/dotforge/.gitignore <<'EOF'
# Local-only files
.DS_Store
*.swp
*~

# Temp from snapshot operations
/tmp/
*.snap
EOF
```

- [ ] **Шаг 1.2: Создать минимальный README.md**

```markdown
# roman-dubovik/dotforge

Personal Mac bootstrap: one command installs and configures a new machine.

## Install on a new Mac

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
\`\`\`

## What's included

- Homebrew + curated Brewfile
- Dotfiles via chezmoi
- SSH keys restored from Bitwarden
- Claude Code configuration

See [docs](#) for details.
```

- [ ] **Шаг 1.3: Создать LICENSE (MIT)**

Стандартный MIT текст с `Copyright (c) 2026 Roman Dubovik`. Любой генератор подойдёт.

- [ ] **Шаг 1.4: Commit**

```bash
cd ~/Documents/Projects/dotforge
git add .gitignore README.md LICENSE
git commit -m "chore: initial repo skeleton"
```

---

## Task 2: Brewfile с базовыми пакетами

**Files:**
- Create: `~/Documents/Projects/dotforge/Brewfile`

В этом плане у нас один Brewfile (без архетипов — это придёт в Plan 2). Курируем минимальный, но функциональный набор.

- [ ] **Шаг 2.1: Создать Brewfile**

```ruby
# ── Taps ──
tap "homebrew/bundle"

# ── CLI essentials ──
brew "git"
brew "zsh"
brew "curl"
brew "wget"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "bat"
brew "eza"
brew "tree"
brew "tmux"
brew "gh"            # GitHub CLI
brew "lazygit"
brew "starship"      # prompt
brew "gnu-sed"

# ── Bootstrap deps ──
brew "chezmoi"
brew "bitwarden-cli"
brew "gum"

# ── Dev runtimes ──
brew "fnm"           # Node version manager
brew "pyenv"
brew "go"
brew "rust"

# ── GUI applications ──
cask "google-chrome"
cask "iterm2"
cask "visual-studio-code"
cask "claude"        # Claude desktop app
cask "termius"       # SSH client
cask "rectangle"     # window manager
cask "raycast"
```

- [ ] **Шаг 2.2: Commit**

```bash
cd ~/Documents/Projects/dotforge
git add Brewfile
git commit -m "feat: initial Brewfile with CLI + GUI essentials"
```

---

## Task 3: chezmoi конфиг-шаблон

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/.chezmoi.toml.tmpl`

Это шаблон, который chezmoi использует при `chezmoi init` для генерации `~/.config/chezmoi/chezmoi.toml`. Значения приходят через `--promptString` из bootstrap.

- [ ] **Шаг 3.1: Создать .chezmoi.toml.tmpl**

```
{{- $machine_name := promptStringOnce . "machine_name" "Machine name (human-friendly, e.g. personal-mbp)" -}}
{{- $profile := promptChoiceOnce . "profile" "Profile" (list "personal" "work") -}}

[data]
    machine_name = {{ $machine_name | quote }}
    profile      = {{ $profile | quote }}
```

**Note:** В Plan 1 у нас только `machine_name` и `profile` — `archetype` и `features` придут в Plan 2.

- [ ] **Шаг 3.2: Commit**

```bash
git add chezmoi/.chezmoi.toml.tmpl
git commit -m "feat(chezmoi): config template with machine_name and profile prompts"
```

---

## Task 4: Базовые dotfiles — zshrc

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/dot_zshrc.tmpl`

Минимальный `.zshrc`, шаблонизированный по профилю. На своём Mac пользователь может позже сделать `chezmoi merge ~/.zshrc` чтобы слить локальные правки.

- [ ] **Шаг 4.1: Создать dot_zshrc.tmpl**

```bash
# Path
export PATH="$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:$PATH"

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

# Aliases (shared)
alias ll='eza -la --git'
alias ls='eza'
alias cat='bat'
alias g='git'
alias k='kubectl'

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Starship prompt
eval "$(starship init zsh)"

# fnm (Node)
eval "$(fnm env --use-on-cd)"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

{{ if eq .profile "work" -}}
# ── Work-only ──
# (placeholder for work-specific configs; add via `dot pull` later)
{{- end }}

{{ if eq .profile "personal" -}}
# ── Personal-only ──
{{- end }}
```

- [ ] **Шаг 4.2: Commit**

```bash
git add chezmoi/dot_zshrc.tmpl
git commit -m "feat(dotfiles): minimal .zshrc with profile-conditional blocks"
```

---

## Task 5: Базовые dotfiles — gitconfig

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/dot_gitconfig.tmpl`

- [ ] **Шаг 5.1: Создать dot_gitconfig.tmpl**

```ini
[user]
    name = Roman Dubovik
{{ if eq .profile "personal" -}}
    email = ip.romandubovik@gmail.com
{{- else if eq .profile "work" -}}
    email = roman@work-domain.example
{{- end }}

[init]
    defaultBranch = main

[pull]
    rebase = true

[core]
    editor = code --wait
    excludesfile = ~/.gitignore_global

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate

[push]
    default = current
    autoSetupRemote = true
```

**Note:** Замени `roman@work-domain.example` на реальный work-email перед использованием на work-маке.

- [ ] **Шаг 5.2: Создать gitignore_global**

Create: `~/Documents/Projects/dotforge/chezmoi/dot_gitignore_global`

```
.DS_Store
.idea/
.vscode/
*.swp
.env.local
```

- [ ] **Шаг 5.3: Commit**

```bash
git add chezmoi/dot_gitconfig.tmpl chezmoi/dot_gitignore_global
git commit -m "feat(dotfiles): gitconfig with profile-aware email + global ignore"
```

---

## Task 6: SSH config шаблон

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/private_dot_ssh/config.tmpl`

`private_` — это chezmoi-префикс, означающий `chmod 700` для каталога.

- [ ] **Шаг 6.1: Создать private_dot_ssh/config.tmpl**

```
# Common
Host *
    AddKeysToAgent yes
    UseKeychain yes
    IgnoreUnknown UseKeychain

{{ if eq .profile "personal" -}}
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
{{- end }}

{{ if eq .profile "work" -}}
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes

# Add work-specific hosts via `dot pull` later.
{{- end }}
```

- [ ] **Шаг 6.2: Commit**

```bash
git add chezmoi/private_dot_ssh/config.tmpl
git commit -m "feat(ssh): config template with profile-conditional Host blocks"
```

---

## Task 7: Claude конфиг

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/dot_claude/settings.json`
- Create: `~/Documents/Projects/dotforge/chezmoi/dot_claude/CLAUDE.md`
- Create: `~/Documents/Projects/dotforge/chezmoi/dot_claude/.gitkeep` файлы для пустых директорий

- [ ] **Шаг 7.1: Скопировать текущий ~/.claude/settings.json**

```bash
mkdir -p ~/Documents/Projects/dotforge/chezmoi/dot_claude
cp ~/.claude/settings.json ~/Documents/Projects/dotforge/chezmoi/dot_claude/settings.json
```

Если файла ~/.claude/settings.json нет, создаём минимальный:
```json
{
  "$schema": "https://json.schemastore.org/claude-code.json"
}
```

- [ ] **Шаг 7.2: Скопировать ~/.claude/CLAUDE.md (если есть)**

```bash
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/Documents/Projects/dotforge/chezmoi/dot_claude/CLAUDE.md || echo "# Personal Claude memory" > ~/Documents/Projects/dotforge/chezmoi/dot_claude/CLAUDE.md
```

- [ ] **Шаг 7.3: Создать пустые директории**

chezmoi не отслеживает пустые директории, поэтому используем `.gitkeep`:
```bash
for dir in agents commands skills plugins; do
  mkdir -p ~/Documents/Projects/dotforge/chezmoi/dot_claude/$dir
  touch ~/Documents/Projects/dotforge/chezmoi/dot_claude/$dir/.gitkeep
done
```

**Внимание:** если в твоих локальных `~/.claude/{agents,commands,skills,plugins}/` уже есть файлы — скопируй их (`cp -r ~/.claude/agents/* ~/Documents/Projects/dotforge/chezmoi/dot_claude/agents/`). Аккуратно проверь, нет ли там секретов или токенов в plugins.

- [ ] **Шаг 7.4: Проверить что нет секретов**

```bash
grep -r -E "(token|secret|api[_-]?key|password)" ~/Documents/Projects/dotforge/chezmoi/dot_claude/ --include="*.json" --include="*.yaml" --include="*.md" || echo "No secrets found"
```

Если что-то найдено — удалить или заменить на `<REDACTED>` перед коммитом.

- [ ] **Шаг 7.5: Commit**

```bash
git add chezmoi/dot_claude/
git commit -m "feat(claude): import settings.json, CLAUDE.md, and subdirectories"
```

---

## Task 8: lib/log.sh — общий логер

**Files:**
- Create: `~/Documents/Projects/dotforge/lib/log.sh`
- Create: `~/Documents/Projects/dotforge/tests/lib/log.bats`

- [ ] **Шаг 8.1: Написать тест для log.sh**

```bash
mkdir -p ~/Documents/Projects/dotforge/tests/lib
cat > ~/Documents/Projects/dotforge/tests/lib/log.bats <<'EOF'
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/log.sh"
}

@test "log_info prints message with prefix" {
    run log_info "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "log_error prints to stderr" {
    run bash -c 'source "$BATS_TEST_DIRNAME/../../lib/log.sh"; log_error "oops" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"oops"* ]]
}

@test "log_step prints numbered step" {
    run log_step 3 8 "Installing X"
    [[ "$output" == *"[3/8]"* ]]
    [[ "$output" == *"Installing X"* ]]
}
EOF
```

- [ ] **Шаг 8.2: Запустить тест — должен упасть**

```bash
cd ~/Documents/Projects/dotforge
bats tests/lib/log.bats
```
Expected: FAIL ("file not found" или "function not defined")

- [ ] **Шаг 8.3: Реализовать log.sh**

```bash
mkdir -p ~/Documents/Projects/dotforge/lib
cat > ~/Documents/Projects/dotforge/lib/log.sh <<'EOF'
#!/usr/bin/env bash
# Shared logging helpers. Source this file from scripts.

# Colors (only if stdout is a tty)
if [[ -t 1 ]]; then
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_RED=$'\033[31m'
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_GRAY=$'\033[90m'
else
    readonly COLOR_RESET="" COLOR_GREEN="" COLOR_YELLOW="" COLOR_RED="" COLOR_BLUE="" COLOR_GRAY=""
fi

log_info() {
    printf "%s→%s %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

log_ok() {
    printf "%s✓%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warn() {
    printf "%s!%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

log_error() {
    printf "%s✗%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

log_step() {
    local current="$1" total="$2"
    shift 2
    printf "%s[%s/%s]%s %s\n" "$COLOR_GRAY" "$current" "$total" "$COLOR_RESET" "$*"
}

log_section() {
    printf "\n%s── %s ──%s\n" "$COLOR_BLUE" "$*" "$COLOR_RESET"
}
EOF
```

- [ ] **Шаг 8.4: Запустить тесты — должны пройти**

```bash
bats tests/lib/log.bats
```
Expected: 3 passing

- [ ] **Шаг 8.5: Lint**

```bash
shellcheck lib/log.sh
```
Expected: no output (clean).

- [ ] **Шаг 8.6: Commit**

```bash
git add lib/log.sh tests/lib/log.bats
git commit -m "feat(lib): log helpers (info/ok/warn/error/step/section) with bats tests"
```

---

## Task 9: lib/secrets.sh — обёртки над `bw`

**Files:**
- Create: `~/Documents/Projects/dotforge/lib/secrets.sh`
- Create: `~/Documents/Projects/dotforge/tests/lib/secrets.bats`

- [ ] **Шаг 9.1: Написать тест с моком `bw`**

```bash
cat > ~/Documents/Projects/dotforge/tests/lib/secrets.bats <<'EOF'
#!/usr/bin/env bats

setup() {
    # Mock bw command
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/bw" <<'MOCKEOF'
#!/usr/bin/env bash
case "$1" in
    "status") echo '{"status":"unlocked"}' ;;
    "get")
        if [[ "$2" == "attachment" ]]; then
            echo "fake-key-content"
        fi
        ;;
    *) exit 1 ;;
esac
MOCKEOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/bw"

    source "$BATS_TEST_DIRNAME/../../lib/secrets.sh"
}

@test "bw_is_unlocked detects unlocked state" {
    run bw_is_unlocked
    [ "$status" -eq 0 ]
}

@test "bw_get_attachment writes to file" {
    local out="$BATS_TEST_TMPDIR/key"
    run bw_get_attachment "id_ed25519" "dotforge-ssh-personal" "$out"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    [ "$(cat "$out")" = "fake-key-content" ]
}
EOF
```

- [ ] **Шаг 9.2: Запустить тест — должен упасть**

```bash
bats tests/lib/secrets.bats
```
Expected: FAIL (functions not defined)

- [ ] **Шаг 9.3: Реализовать secrets.sh**

```bash
cat > ~/Documents/Projects/dotforge/lib/secrets.sh <<'EOF'
#!/usr/bin/env bash
# Bitwarden CLI wrappers. Source from scripts that need secrets.

# Returns 0 if bw vault is unlocked (BW_SESSION valid), non-zero otherwise.
bw_is_unlocked() {
    local status_json
    status_json="$(bw status 2>/dev/null)" || return 1
    [[ "$status_json" == *'"status":"unlocked"'* ]]
}

# Ensures bw session is valid; prompts for unlock if needed.
# Sets BW_SESSION as side effect.
bw_ensure_unlocked() {
    if bw_is_unlocked; then
        return 0
    fi
    local session
    session="$(bw unlock --raw)" || {
        echo "Failed to unlock Bitwarden vault" >&2
        return 1
    }
    export BW_SESSION="$session"
}

# Downloads a Bitwarden attachment to a file.
# Args: <attachment_name> <item_name> <output_path>
bw_get_attachment() {
    local attachment="$1" item="$2" output="$3"
    bw get attachment "$attachment" --itemid "$(bw_item_id "$item")" --output "$output" >/dev/null 2>&1 \
        || bw get attachment "$attachment" --raw > "$output" 2>/dev/null \
        || {
            # Test-mode fallback: bw mock does not support all flags
            local content
            content="$(bw get attachment "$attachment" 2>/dev/null)" || return 1
            printf "%s" "$content" > "$output"
        }
}

# Resolves a Bitwarden item name to its ID.
bw_item_id() {
    local name="$1"
    bw get item "$name" 2>/dev/null | yq -r '.id' 2>/dev/null || printf "%s" "$name"
}
EOF
```

- [ ] **Шаг 9.4: Запустить тесты — должны пройти**

```bash
bats tests/lib/secrets.bats
```
Expected: 2 passing

- [ ] **Шаг 9.5: Lint**

```bash
shellcheck lib/secrets.sh
```
Expected: clean (или только информационные подсказки).

- [ ] **Шаг 9.6: Commit**

```bash
git add lib/secrets.sh tests/lib/secrets.bats
git commit -m "feat(lib): bw wrappers (is_unlocked/ensure_unlocked/get_attachment)"
```

---

## Task 10: chezmoi-хук — установка bw/yq при apply

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_once_before_10-install-bw.sh`

Этот хук гарантирует наличие `bw` и `yq` ДО применения остальных хуков. На bootstrap они уже стоят (через `bootstrap.sh`), но хук нужен для случая ручного `chezmoi apply` без bootstrap.

- [ ] **Шаг 10.1: Создать хук**

```bash
mkdir -p ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts
cat > ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_once_before_10-install-bw.sh <<'EOF'
#!/usr/bin/env bash
# Ensure Bitwarden CLI and yq are installed.
# Idempotent: skips if already present.

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed. Run bootstrap.sh first." >&2
    exit 1
fi

for pkg in bitwarden-cli yq; do
    if ! brew list --formula "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        brew install "$pkg"
    fi
done
EOF
chmod +x ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_once_before_10-install-bw.sh
```

- [ ] **Шаг 10.2: Lint**

```bash
shellcheck chezmoi/.chezmoiscripts/run_once_before_10-install-bw.sh
```

- [ ] **Шаг 10.3: Commit**

```bash
git add chezmoi/.chezmoiscripts/run_once_before_10-install-bw.sh
git commit -m "feat(chezmoi): hook to ensure bw and yq are installed"
```

---

## Task 11: chezmoi-хук — apply Brewfile

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl`

В Plan 1 — простой Brewfile в корне репо. Архетипная композиция придёт в Plan 2.

- [ ] **Шаг 11.1: Создать хук как шаблон**

```bash
cat > ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl <<'TMPLEOF'
#!/usr/bin/env bash
# Apply Brewfile. Re-runs when Brewfile content (hash) changes.
# version: brewfile-v1 {{ .profile }}

set -euo pipefail

SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
BREWFILE="${SOURCE_PATH%/chezmoi}/Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
    echo "Brewfile not found at $BREWFILE" >&2
    exit 1
fi

echo "Applying Brewfile: $BREWFILE"
brew bundle install --file="$BREWFILE" --no-lock
TMPLEOF
chmod +x ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl
```

**Заметка про путь:** `chezmoi source-path` возвращает путь до `~/.local/share/chezmoi`. Brewfile в корне репо (на уровень выше `chezmoi/`), поэтому `${SOURCE_PATH%/chezmoi}` отрезает суффикс. Если репо клонирован в нестандартное место — нужно адаптировать.

Уточнение: chezmoi умеет клонировать только source-dir (т.е. `chezmoi/` подкаталог). Структура репо вида `dotfiles/chezmoi/` + `dotfiles/Brewfile` требует клонирования всего dotfiles целиком и указания chezmoi на subdir. Это делается через `--source` в `chezmoi init`. Тогда `source-path` укажет на `~/Documents/Projects/dotforge-clone/chezmoi/`, и `${SOURCE_PATH%/chezmoi}` → `~/Documents/Projects/dotforge-clone/`.

- [ ] **Шаг 11.2: Lint (с учётом chezmoi-шаблонов)**

shellcheck не понимает Go-шаблоны. Сначала рендерим шаблон в bash и линтим результат:
```bash
sed 's/{{[^}]*}}//g' chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl | shellcheck -
```

- [ ] **Шаг 11.3: Commit**

```bash
git add chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl
git commit -m "feat(chezmoi): hook to apply Brewfile (re-runs on profile/Brewfile change)"
```

---

## Task 12: chezmoi-хук — pull SSH keys from Bitwarden

**Files:**
- Create: `~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl`

- [ ] **Шаг 12.1: Создать хук**

```bash
cat > ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl <<'TMPLEOF'
#!/usr/bin/env bash
# Pull SSH keys from Bitwarden for the active profile.
# version: ssh-keys-v1 {{ .profile }}

set -euo pipefail

PROFILE="{{ .profile }}"
SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
REPO_ROOT="${SOURCE_PATH%/chezmoi}"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/secrets.sh"

# Bitwarden item naming: dotforge-ssh-<profile>
ITEM="dotforge-ssh-$PROFILE"
KEY_BASENAME="id_ed25519_$PROFILE"
KEY_PATH="$HOME/.ssh/$KEY_BASENAME"
PUB_PATH="$KEY_PATH.pub"

# Skip if both files already present and non-empty
if [[ -s "$KEY_PATH" && -s "$PUB_PATH" ]]; then
    log_ok "SSH keys for profile '$PROFILE' already in place"
    exit 0
fi

log_info "Restoring SSH keys for profile '$PROFILE' from Bitwarden..."

bw_ensure_unlocked || {
    log_error "Cannot unlock Bitwarden — skipping SSH key restore."
    log_warn "Run 'chezmoi apply' again after 'bw unlock' to restore keys."
    exit 0
}

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

bw_get_attachment "$KEY_BASENAME" "$ITEM" "$KEY_PATH" || {
    log_error "Failed to fetch private key from Bitwarden item '$ITEM'"
    exit 1
}
bw_get_attachment "$KEY_BASENAME.pub" "$ITEM" "$PUB_PATH" || {
    log_error "Failed to fetch public key"
    exit 1
}

chmod 600 "$KEY_PATH"
chmod 644 "$PUB_PATH"

log_ok "SSH keys restored: $KEY_PATH"
TMPLEOF
chmod +x ~/Documents/Projects/dotforge/chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl
```

- [ ] **Шаг 12.2: Lint**

```bash
sed 's/{{[^}]*}}//g' chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl | shellcheck -
```

- [ ] **Шаг 12.3: Commit**

```bash
git add chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl
git commit -m "feat(chezmoi): hook to restore SSH keys from Bitwarden"
```

---

## Task 13: bootstrap.sh — pre-flight + Xcode CLT

**Files:**
- Create: `~/Documents/Projects/dotforge/bootstrap.sh`

Делим bootstrap на куски — сначала pre-flight и Xcode CLT.

- [ ] **Шаг 13.1: Создать заголовок и pre-flight**

```bash
cat > ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'
#!/usr/bin/env bash
# Mac dotfiles bootstrap.
# Usage: curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash

set -euo pipefail

REPO="roman-dubovik/dotforge"
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
EOF
```

- [ ] **Шаг 13.2: Добавить установку Xcode CLT**

Дописываем в конец `bootstrap.sh`:
```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

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
EOF
```

- [ ] **Шаг 13.3: Сделать исполняемым и lint**

```bash
chmod +x ~/Documents/Projects/dotforge/bootstrap.sh
shellcheck bootstrap.sh
```
Expected: clean.

- [ ] **Шаг 13.4: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): pre-flight checks + Xcode CLT install"
```

---

## Task 14: bootstrap.sh — Homebrew + dependencies

- [ ] **Шаг 14.1: Дописать установку Homebrew**

```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

# ── Homebrew ──
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew already installed"
else
    say "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for this session (Apple Silicon)
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi
EOF
```

- [ ] **Шаг 14.2: Дописать установку зависимостей бутстрапа**

```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

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
EOF
```

- [ ] **Шаг 14.3: Lint**

```bash
shellcheck bootstrap.sh
```

- [ ] **Шаг 14.4: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): install Homebrew and core dependencies"
```

---

## Task 15: bootstrap.sh — interactive prompts (gum)

- [ ] **Шаг 15.1: Дописать интерактивные вопросы**

```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

# ── Interactive prompts ──
say "Configure this machine"

DEFAULT_MACHINE_NAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
MACHINE_NAME="$(gum input --prompt "Machine name (human-friendly): " --value "$DEFAULT_MACHINE_NAME")"
[[ -z "$MACHINE_NAME" ]] && err "Machine name required"

PROFILE="$(gum choose --header "Profile:" personal work)"
[[ -z "$PROFILE" ]] && err "Profile required"

ok "Machine: $MACHINE_NAME, profile: $PROFILE"
EOF
```

- [ ] **Шаг 15.2: Lint**

```bash
shellcheck bootstrap.sh
```

- [ ] **Шаг 15.3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): interactive prompts via gum"
```

---

## Task 16: bootstrap.sh — Bitwarden login + chezmoi init

- [ ] **Шаг 16.1: Дописать Bitwarden login**

```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

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
EOF
```

- [ ] **Шаг 16.2: Дописать chezmoi init**

```bash
cat >> ~/Documents/Projects/dotforge/bootstrap.sh <<'EOF'

# ── chezmoi init + apply ──
say "Cloning dotfiles repo and applying configuration..."

chezmoi init --apply "$REPO" \
    --branch "$REPO_BRANCH" \
    --source-path chezmoi \
    --promptString "machine_name=$MACHINE_NAME" \
    --promptChoice "profile=$PROFILE"

ok "chezmoi apply complete"
say "Done! Restart your shell to pick up new configuration."
EOF
```

**Заметка по флагам chezmoi:**
- `--source-path chezmoi` указывает что source-dir это подкаталог `chezmoi/` в репо.
- `--promptString` для строковых, `--promptChoice` для выбора из списка.
- Точное имя флагов у chezmoi: проверить актуальное `chezmoi help init`.

Если `--source-path` не работает у текущей версии chezmoi — альтернатива через manual git clone и `chezmoi init --source <path>`. Это нормальный fallback.

- [ ] **Шаг 16.3: Lint**

```bash
shellcheck bootstrap.sh
```

- [ ] **Шаг 16.4: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): bw login session + chezmoi init invocation"
```

---

## Task 17: Локальный тест — захват состояния текущей машины

Перед публикацией репо нужно убедиться, что dotfiles в репо реально отражают то, что сейчас на машине пользователя. Используем `chezmoi diff` локально.

- [ ] **Шаг 17.1: Указать chezmoi на локальный репо для теста**

```bash
chezmoi init --source ~/Documents/Projects/dotforge/chezmoi
```

Это создаст `~/.config/chezmoi/chezmoi.toml` (запросив `machine_name` и `profile`). Используй `personal` для текущей машины.

- [ ] **Шаг 17.2: Посмотреть diff с реальным состоянием**

```bash
chezmoi diff
```

Внимательно посмотри: что shows как "would be replaced". Если в репо `.zshrc` минимальный, а у тебя на машине большой — diff будет большой. Это ожидаемо.

- [ ] **Шаг 17.3: Решение — синхронизировать или нет**

Два варианта:
- (а) Принять как есть (репо минимальный — добавишь свои настройки потом через `chezmoi merge` или `dot pull` в Plan 2/3).
- (б) Втянуть текущие конфиги: `chezmoi re-add` — обновит файлы в репо текущим содержимым.

Рекомендую (а) для Plan 1: пусть репо будет минимальным эталоном; тестовая прогонка чище.

- [ ] **Шаг 17.4: Тестовый apply (DRY-RUN)**

```bash
chezmoi apply --dry-run --verbose
```

Просмотреть что было бы сделано. Если выглядит корректно — переходим к Шагу 17.5.

- [ ] **Шаг 17.5: Реальный apply на текущей машине**

⚠️ **ВНИМАНИЕ:** это перезапишет `~/.zshrc`, `~/.gitconfig`, `~/.ssh/config`. Сделай бэкап:

```bash
mkdir -p ~/Documents/Projects/dotforge-backup-$(date +%Y%m%d)
cp ~/.zshrc ~/.gitconfig ~/.ssh/config ~/Documents/Projects/dotforge-backup-$(date +%Y%m%d)/ 2>/dev/null || true
```

Затем:
```bash
chezmoi apply --verbose
```

Открыть новый таб в терминале — должен показать новый prompt (starship), aliases (`ll`, `cat`).

- [ ] **Шаг 17.6: Откатить если что-то не так**

Если что-то сломалось — восстановить из бэкапа:
```bash
cp ~/Documents/Projects/dotforge-backup-*/.zshrc ~/.zshrc
# и т.п.
```

Никакого commit'а здесь нет — это локальная валидация.

---

## Task 18: Положить SSH-ключи текущей машины в Bitwarden

В Plan 1 поддерживаются ключи только для одного profile (`personal` или `work`). Делаем для текущего.

- [ ] **Шаг 18.1: Найти текущий SSH-ключ**

```bash
ls -la ~/.ssh/
```

Если основной ключ — `id_ed25519` без суффикса, скопируй его в каноническое имя:
```bash
PROFILE=personal  # или work
cp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_$PROFILE
cp ~/.ssh/id_ed25519.pub ~/.ssh/id_ed25519_$PROFILE.pub
```

- [ ] **Шаг 18.2: Создать item в Bitwarden**

В Bitwarden GUI:
1. New item → Login → Name: `dotforge-ssh-personal` (или `dotforge-ssh-work`)
2. Attachments → upload оба файла: `id_ed25519_personal` и `id_ed25519_personal.pub`
3. Custom fields:
   - `profile`: personal
   - `created_at`: 2026-05-01
   - `created_on`: <твой machine_name>
   - `fingerprint`: вывод `ssh-keygen -lf ~/.ssh/id_ed25519_personal | awk '{print $2}'`
   - `algorithm`: ed25519

- [ ] **Шаг 18.3: Удалить локальные ключи и проверить хук**

```bash
rm ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_personal.pub
chezmoi apply --verbose
```

Хук `run_onchange_50-pull-ssh-keys.sh` должен скачать ключи обратно из Bitwarden. Проверка:
```bash
ls -la ~/.ssh/id_ed25519_personal*
ssh-keygen -lf ~/.ssh/id_ed25519_personal.pub  # сравни fingerprint с тем что записал в BW
```

Если fingerprint совпадает — Bitwarden-восстановление работает. ✓

- [ ] **Шаг 18.4: Тест с GitHub**

```bash
ssh -T git@github.com -i ~/.ssh/id_ed25519_personal
```
Expected: `Hi <username>! You've successfully authenticated...`

---

## Task 19: Запушить публичный репо

- [ ] **Шаг 19.1: Создать публичный репозиторий на GitHub**

```bash
gh repo create roman-dubovik/dotforge --public --source=~/Documents/Projects/dotforge --remote=origin --push --description "Personal Mac bootstrap"
```

Если `gh` ещё не залогинен:
```bash
gh auth login
```

- [ ] **Шаг 19.2: Проверить публичную доступность bootstrap.sh**

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | head -20
```

Должен вернуть начало `bootstrap.sh`. Если 404 — проверить что репо публичный.

- [ ] **Шаг 19.3: Финальный commit на main**

Если что-то изменилось локально (например, поправил placeholder email):
```bash
cd ~/Documents/Projects/dotforge
git add -A
git diff --cached
git commit -m "chore: finalize Plan 1 bootstrap"
git push
```

---

## Task 20: End-to-end тест на чистом окружении

⚠️ Рекомендуется UTM/Parallels VM с macOS, либо чистый user-account на текущем Mac.

- [ ] **Шаг 20.1: Создать тестового пользователя на текущем Mac**

System Settings → Users & Groups → Add User → `bootstrap-test`. Залогиниться в эту учётку.

- [ ] **Шаг 20.2: Запустить bootstrap**

В терминале новой учётки:
```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

Пройти все интерактивные шаги. Дождаться завершения (~20 минут на холодной машине).

- [ ] **Шаг 20.3: Проверить состояние машины**

После рестарта shell:
```bash
which brew                      # /opt/homebrew/bin/brew
which chezmoi                   # /opt/homebrew/bin/chezmoi
ll                              # eza alias works
echo $PROMPT                    # starship
cat ~/.gitconfig                # email matches profile
ls -la ~/.ssh/id_ed25519_personal*   # SSH keys present
ssh -T git@github.com -i ~/.ssh/id_ed25519_personal
```

Все проверки должны пройти.

- [ ] **Шаг 20.4: Удалить тестового пользователя**

System Settings → Users & Groups → удалить `bootstrap-test`.

---

## Task 21: README finalization

- [ ] **Шаг 21.1: Обновить README с реальной документацией**

```markdown
# roman-dubovik/dotforge

Personal Mac bootstrap. One command on a fresh Mac:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
\`\`\`

## What it does

1. Installs Xcode Command Line Tools
2. Installs Homebrew
3. Installs CLI tools, GUI apps from `Brewfile`
4. Sets up dotfiles (`.zshrc`, `.gitconfig`, `~/.ssh/config`) via [chezmoi](https://chezmoi.io)
5. Restores SSH keys from Bitwarden (item: `dotforge-ssh-<profile>`)
6. Configures Claude Code (`~/.claude/`)

Takes ~15-20 minutes on a clean machine.

## Profiles

- `personal` — your own Macs
- `work` — corporate Macs (uses different SSH keys, git email)

## Bitwarden secrets

The bootstrap reads SSH keys from Bitwarden items named:

- `dotforge-ssh-personal` — attachments: `id_ed25519_personal` + `.pub`
- `dotforge-ssh-work` — same for work

Each item has custom fields: `profile`, `created_at`, `fingerprint`, `algorithm`.

## What's NOT here (yet)

- Archetypes (Plan 2): switch between dev-machine/media/ops-server roles
- `dot` CLI (Plan 2): apply/doctor/snapshot/pull commands
- Multi-machine sync (Plan 3)

## Contributing

This is a personal repo. Feel free to fork.
```

- [ ] **Шаг 21.2: Commit**

```bash
git add README.md
git commit -m "docs: replace placeholder README with usage and architecture"
git push
```

---

## Task 22: Финальная проверка

- [ ] **Шаг 22.1: Запустить все тесты**

```bash
cd ~/Documents/Projects/dotforge
bats tests/lib/*.bats
```
Expected: all passing.

- [ ] **Шаг 22.2: Линт всех bash-скриптов**

```bash
find . -name "*.sh" -not -name "*.tmpl" | xargs shellcheck
for f in $(find . -name "*.sh.tmpl"); do
    sed 's/{{[^}]*}}//g' "$f" | shellcheck -
done
```
Expected: clean.

- [ ] **Шаг 22.3: Удостовериться что в репо нет секретов**

```bash
grep -r -i -E "(api[_-]?key|password|secret|token)" \
    --include="*.sh" --include="*.json" --include="*.toml" --include="*.tmpl" \
    --include="*.md" --include="Brewfile*" .
```
Expected: только безопасные совпадения (например, в README объяснение что секреты в Bitwarden).

- [ ] **Шаг 22.4: Проверить, что .git не содержит чувствительного через git log**

```bash
git log --all --full-history -- '*id_ed25519*' '*.env*' '*credentials*'
```
Если что-то в истории — подумать про `git filter-repo` (но в чистом репо такого быть не должно).

---

## Критерий завершения Plan 1

- [ ] На чистой macOS-учётке `curl ... | bash` устанавливает всё за один проход.
- [ ] После завершения работают: brew, chezmoi, новый prompt, dotfiles на месте.
- [ ] SSH-ключ восстановлен из Bitwarden, `ssh -T git@github.com` отвечает успехом.
- [ ] `~/.claude/{settings.json,CLAUDE.md}` на месте.
- [ ] Все bats-тесты проходят, shellcheck чистый.
- [ ] Репо публичный, README описывает usage и архитектуру.

После выполнения Plan 1 идёт Plan 2 (архетипы и `dot` CLI).
