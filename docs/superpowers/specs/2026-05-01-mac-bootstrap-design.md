# Mac Bootstrap & Configuration Sync — дизайн

**Дата:** 2026-05-01
**Автор:** Roman Dubovik
**Статус:** Draft, ready for review

---

## 1. Цели и не-цели

### Цели

1. **Одна команда на новой машине** — на свежем Mac выполняется `curl ... | bash`, и через ~15-20 минут машина полностью настроена: приложения установлены, дотфайлы развёрнуты, SSH-ключи подняты из Bitwarden, Claude Code настроен, macOS-дефолты применены.
2. **Декларативное состояние** — конфигурация машины описана в git (приложения, дотфайлы, defaults), секреты — в Bitwarden. Нет шагов "сделай руками".
3. **Текущий Mac как эталон** — есть команда, которая снимает текущее состояние машины обратно в репо (`dot snapshot`).
4. **Сравнение машин** — `dot doctor` показывает что отличается от состояния в репо: дотфайлы, Brew-пакеты, macOS-defaults, SSH-ключи. Подсвечивает локальные изменения, которые ещё не в репо.
5. **Аддитивный merge с другой машины** — `dot pull <path>` втягивает локальный файл/настройку с одной машины в репо, чтобы потом раскатить на других.
6. **Несколько машин с общим ядром** — две оси настройки:
   - **Profile** (`personal`/`work`) — контекст идентичности (какие секреты, work-only конфиги).
   - **Archetype** (`dev-machine`/`minimal`/...) — роль машины (какой стек приложений).
   - **Feature flags** внутри архетипа — опциональные тогглы (`docker-desktop`, `local-llm`).
7. **Идемпотентность** — все команды можно запускать повторно, на уже настроенной машине bootstrap = no-op.

### Не-цели

- Бэкап пользовательских данных (фото, документы, рабочие проекты) — это задача Time Machine / iCloud.
- Перенос auth-токена Claude Code — пользователь логинится в Claude вручную после bootstrap.
- Перенос GPG (не используется).
- Перенос истории Claude (`~/.claude/projects/`) — большие, не нужны.
- Linux/Windows. Только macOS.
- Управление через nix/declarative-only — bash + chezmoi, прагматичный подход.

---

## 2. Архитектура

Три слоя с чёткими границами:

```
┌──────────────────────────────────────────────────────────┐
│  1. BOOTSTRAP — точка входа на чистом Mac                │
│     bootstrap.sh  (curl … | bash)                        │
│     • Xcode CLT, Homebrew, chezmoi, bw, yq, gum          │
│     • Спрашивает: machine_name, profile, archetype, features │
│     • Передаёт управление chezmoi                        │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  2. CONFIG — декларативное состояние, в публичном git    │
│     • chezmoi (дотфайлы, шаблоны)                        │
│     • Brewfile.* (приложения, по архетипу/фиче)          │
│     • macos/*.sh (defaults write, по архетипу/фиче)      │
│     • runtimes/*.sh (fnm, pyenv и т.п.)                  │
│     • archetypes/*.yaml (декларации архетипов)           │
│     • ssh/manifest.yaml (метаданные ключей, без секретов)│
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  3. SECRETS — Bitwarden                                  │
│     • SSH приватные ключи (по profile)                   │
│     • Локальные .env'ы рабочих проектов                  │
│     • Достаются через `bw` в chezmoi-хуках               │
└──────────────────────────────────────────────────────────┘
```

**Ключевые границы:**
- **В git-репо нет секретов.** Только публичные ключи, метаданные, конфиги, references на BW item IDs.
- **Bootstrap не знает про конкретные приложения.** Он только готовит почву и запускает chezmoi.
- **chezmoi оркестрирует всё** через свои хуки (`run_once_*`, `run_onchange_*`).
- **Идемпотентность повсюду.** Каждый шаг проверяет состояние перед действием.

---

## 3. Модель данных: профили, архетипы, фичи

### 3.1. Profile — контекст идентичности

Машина имеет **один профиль**. Профиль определяет:
- Какие SSH-ключи поднимаются (`personal` vs `work`).
- Какие per-company конфиги активны (например, `git-vpn-proxy` для `work`).
- Какие Bitwarden-айтемы используются.

Профили: `personal`, `work` (расширяемо в будущем).

### 3.2. Archetype — роль машины

Машина имеет **один архетип**. Архетип — декларативный YAML в `archetypes/<name>.yaml`, описывающий:
- Какие Brewfile-блоки ставятся (ядро архетипа).
- Какие dotfile-модули включены.
- Какие macOS-defaults применяются.
- Какие dev-runtime ставятся.
- Какие feature-флаги доступны (опционально).

**Композиция через `extends:`** — архетип может наследовать другой:
```
minimal → dev-machine → dev-with-AI
```

Стандартные архетипы:
- `minimal` — корневой архетип. Базовые дотфайлы (zsh, git), `~/.ssh/config`, Claude-конфиг, минимальный CLI (jq, ripgrep). Не наследует ничего.
- `dev-machine` — `extends: minimal` + dev-стек (языки, IDE).
- `media` — `extends: minimal` + media-софт (без dev).
- `ops-server` — `extends: minimal` без GUI-приложений (для headless-машин).

**Примечание.** Xcode CLT, Homebrew, `bw`, `chezmoi`, `yq`, `gum` ставятся в `bootstrap.sh` **до** запуска chezmoi. Это инфраструктура bootstrap, не часть архетипа.

### 3.3. Feature flags — опциональные тогглы

Внутри архетипа объявлены **опциональные фичи**. Пример из `dev-machine.yaml`:

```yaml
features:
  docker-desktop:
    description: "Docker Desktop (~600 MB)"
    brewfiles: [Brewfile.docker]

  jetbrains:
    description: "JetBrains Toolbox + IDE-плагины"
    brewfiles: [Brewfile.jetbrains]
    dotfile_modules: [editor/jetbrains]

  local-llm:
    description: "Ollama + локальные модели"
    brewfiles: [Brewfile.llm]
    runtimes: [ollama-models]

  cursor-ide:
    description: "Cursor (AI-редактор)"
    brewfiles: [Brewfile.cursor]
```

Фичи — это **именованные дельты** к архетипу. На bootstrap пользователь выбирает чек-боксами какие включить. Сохраняется в `chezmoi.toml` как массив строк.

### 3.4. Хранение выбранных значений

`~/.config/chezmoi/chezmoi.toml`:
```toml
[data]
  machine_name = "my-new-mac"        # human-friendly имя для манифестов
  profile      = "personal"
  archetype    = "dev-machine"
  features     = ["local-llm", "cursor-ide"]
```

Это единый источник правды для шаблонов chezmoi.

**`machine_name` vs `chezmoi.hostname`.** chezmoi предоставляет встроенную `.chezmoi.hostname` от ОС (например, `MacBook-Pro-7.local`). `machine_name` — это **отдельное человеко-читаемое имя**, выбираемое при bootstrap (например, `personal-mbp` или `work-mbp`). Используется для записей в `ssh/manifest.yaml` (`used_on`, `created_on`) — чтобы было понятно, что за машина, без техногенных суффиксов macOS.

### 3.5. Полная схема архетипа

```yaml
# archetypes/dev-machine.yaml
name: dev-machine
description: "Полный dev-стек (CLI, языки, IDE)"
extends: minimal                # композиция

# ── ОБЯЗАТЕЛЬНОЕ ЯДРО ──
brewfiles:
  - Brewfile.dev-core           # ripgrep, fzf, gh, lazygit
  - Brewfile.languages-toolchain
  - Brewfile.gui-dev-core       # vscode

dotfile_modules:
  - shell/dev-aliases
  - editor/vscode

macos_modules:
  - dev-defaults                # show-hidden-files, faster key repeat

runtimes:
  - node                        # fnm + LTS
  - python                      # pyenv + 3.12
  - go
  - rust

# ── ОПЦИОНАЛЬНОЕ ──
features:
  docker-desktop:
    description: "..."
    brewfiles: [Brewfile.docker]

  jetbrains:
    brewfiles: [Brewfile.jetbrains]
    dotfile_modules: [editor/jetbrains]

  local-llm:
    brewfiles: [Brewfile.llm]
    runtimes: [ollama-models]

  cursor-ide:
    brewfiles: [Brewfile.cursor]
```

---

## 4. Компоненты

### 4.1. `bootstrap.sh` — точка входа

Запускается через `curl -fsSL https://raw.githubusercontent.com/romandubovik/dotforge/main/bootstrap.sh | bash` (URL шортится через `dotforge.romandubovik.dev/install` если есть домен).

**Шаги:**
1. Проверка macOS, версии, наличия `xcode-select`. Установка Xcode CLT (диалог macOS, ~5 мин).
2. Установка Homebrew (если нет).
3. Установка `chezmoi`, `bw`, `yq`, `gum` (для интерактивного UI) через Homebrew.
4. Интерактивные вопросы:
   - Machine name (human-friendly, например `personal-mbp`; по умолчанию `chezmoi.hostname`).
   - Profile (`personal` / `work`).
   - Archetype — выбор из `archetypes/*.yaml`.
   - Features — мульти-чекбокс из выбранного архетипа.
   - Bitwarden email + master password.
5. **Логин в Bitwarden:** `bw login`, экспорт `BW_SESSION` в env.
6. **Передача значений в `chezmoi init`** через флаги `--promptString` / `--promptStringList`. `.chezmoi.toml.tmpl` использует эти promptString-ы для генерации `~/.config/chezmoi/chezmoi.toml`. Bootstrap **не пишет конфиг руками**.
7. `chezmoi init --apply romandubovik/dotforge --promptString profile=$P --promptString archetype=$A --promptStringList features=$F ...` — клонирует репо и применяет. `BW_SESSION` доступен всем хукам.
8. После завершения — `bw lock`.

**Идемпотентность:** на повторном запуске bootstrap пропускает уже установленное (Homebrew, CLT, chezmoi). Если `chezmoi.toml` уже есть — спрашивает "переконфигурировать?" с дефолтом No.

**Bootstrap не использует `dot` CLI** — он работает напрямую с chezmoi и хуками. `dot` появляется в `~/.local/bin/` после первого `chezmoi apply` и доступен для последующих операций (snapshot/doctor/switch).

### 4.2. chezmoi и его хуки

Source-директория: `chezmoi/` в корне репо. chezmoi умеет:
- Шаблонизировать файлы (Go templates с доступом к `.profile`, `.archetype`, `.features`).
- Условные файлы (`run_once_before_*` запускается один раз перед apply, `run_onchange_*` — при изменении содержимого).
- Удалять файлы, которые больше не рендерятся (важно для `dot archetype switch`).
- Шифрованные файлы (не используем — секреты в Bitwarden).

**Структура хуков** (`chezmoi/.chezmoiscripts/`):
- `run_once_before_10-install-bw.sh` — проверка/установка Bitwarden CLI и `yq`.
- `run_onchange_20-apply-brewfiles.sh.tmpl` — собирает все нужные Brewfile (ядро архетипа + фичи), запускает `brew bundle install`.
- `run_onchange_30-apply-macos-defaults.sh.tmpl` — собирает и запускает все macos-модули.
- `run_onchange_40-install-runtimes.sh.tmpl` — fnm/pyenv и языки по списку.
- `run_onchange_50-pull-ssh-keys.sh.tmpl` — использует `BW_SESSION` (унаследованную из bootstrap) → `bw get attachment` для ключей профиля → `chmod 600`. Если `BW_SESSION` не выставлен (повторный запуск без bootstrap) — запрашивает `bw unlock` интерактивно. Шаблон с `# version: {{ .profile }}` чтобы пересобирался при смене профиля.
- `run_onchange_70-install-vscode-extensions.sh.tmpl` — устанавливает расширения VSCode/Cursor из `~/.config/Code/extensions.txt` (см. 4.7.1). Активен только если в архетипе/фичах включён модуль `editor/vscode` или `editor/cursor`.

**Claude-конфиг хука не имеет** — копируется через стандартный `chezmoi apply` из `chezmoi/dot_claude/` (см. 4.7).

Хуки вычитывают `chezmoi.toml`, парсят `archetypes/<name>.yaml` через `yq`, рекурсивно разрешают `extends:`, собирают эффективный набор brewfiles/modules/runtimes (с учётом активных фич).

**Триггер хуков при смене архетипа.** chezmoi триггерит `run_onchange_*` по хешу содержимого скрипта. Чтобы хук пересобирался при смене значений в `chezmoi.toml`, каждый `run_onchange_*` скрипт — это **шаблон** (`.tmpl`), в начале которого вшита версия:
```bash
# version: {{ .archetype }} {{ .features | toJson }} {{ .profile }}
```
Когда пользователь меняет архетип/фичи/профиль, chezmoi перерендерит скрипт, его хеш изменится, и хук гарантированно запустится.

**Сессия Bitwarden.** Bootstrap (см. 4.1) делает `bw login` один раз и экспортит `BW_SESSION` в env. chezmoi запускается из этого окружения, все хуки используют существующий session. Это избегает повторных запросов мастер-пароля. После завершения bootstrap делает `bw lock`. На повторных запусках (`dot apply` без bootstrap) — хуки запросят `bw unlock` интерактивно если нужны секреты.

### 4.3. Brewfile-модули

В корне:
```
Brewfile.dev-core
Brewfile.languages-toolchain
Brewfile.gui-dev-core
Brewfile.docker
Brewfile.jetbrains
Brewfile.llm
Brewfile.cursor
Brewfile.media
Brewfile.minimal
...
```

Каждый Brewfile — стандартный синтаксис `brew "..."`, `cask "..."`, `mas "..."` (для App Store). Хук `apply-brewfiles.sh` склеивает выбранные в один временный Brewfile, запускает `brew bundle install --file=<tmp>`.

**Семантика установки vs удаления:**
- `brew bundle install` **только доустанавливает** недостающее. Пакеты, имеющиеся локально, но отсутствующие в Brewfile, **не трогаются** (считаются "unmanaged" — например, поставлены вручную для эксперимента).
- Удаление лишних пакетов делается **явно** через `dot archetype switch <name> --cleanup` или `dot brew cleanup`. По умолчанию `--cleanup` выключен.
- Перед `--cleanup` показывается полный список того, что будет удалено, с подтверждением.

**Снапшот:** `dot snapshot` запускает `brew bundle dump --force --file=/tmp/Brewfile.snap` и сравнивает с эффективным репо-набором. Для **новых** пакетов диалог: "Какие изменения куда положить?" — пользователь распределяет по существующим Brewfile. Для **исчезнувших** пакетов (есть в репо, нет локально) — предлагает удалить из Brewfile или оставить (если пакет временно удалён).

### 4.4. macOS defaults

`macos/<module>.sh` — каждый модуль это набор `defaults write` команд + (опционально) функция `read_state` для doctor'а:

```bash
# macos/dev-defaults.sh
apply() {
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write NSGlobalDomain KeyRepeat -int 2
}

read_state() {
  echo "AppleShowAllFiles=$(defaults read com.apple.finder AppleShowAllFiles)"
  echo "KeyRepeat=$(defaults read NSGlobalDomain KeyRepeat)"
}
```

Doctor сравнивает текущий вывод `read_state` с ожидаемым (хардкоднутым в скрипте).

**Ограничение `dot snapshot` для macOS-defaults.** Невозможно автоматически "обнаружить все вручную выставленные defaults" — пространство ключей огромно и без хардкода списка непонятно что искать. `dot snapshot` macOS-defaults **не сканирует**. Пользователь добавляет новые defaults явно:

```
$ dot macos add com.apple.dock tilesize --module dev-defaults
✓ Added to macos/dev-defaults.sh:
    defaults write com.apple.dock tilesize -int 64
✓ Added to read_state() block.
```

Команда читает текущее значение через `defaults read`, угадывает тип (`-int`/`-bool`/`-string`), вставляет в `apply()` и `read_state()` указанного модуля. После этого `dot doctor` начинает следить за этим ключом.

### 4.5. Dev runtimes

`runtimes/<name>.sh`:
- `node.sh` — ставит fnm (если нет) → `fnm install --lts`.
- `python.sh` — pyenv → 3.12.
- `go.sh`, `rust.sh` — через Homebrew.
- `ollama-models.sh` — `ollama pull llama3.1` и т.п.

Идемпотентны (проверяют `command -v`, `node -v`).

### 4.6. SSH-ключи

**Naming on disk:**
```
~/.ssh/id_ed25519_personal
~/.ssh/id_ed25519_personal.pub
~/.ssh/id_ed25519_work
~/.ssh/id_ed25519_work.pub
```

Канонических `id_ed25519` без суффикса — нет.

**Comment в `.pub`-файле** — стандартизирован: `roman@<hostname>-YYYY-MM-DD`. Виден в GitHub UI и при `ssh-add -L`.

**`~/.ssh/config`** — шаблон chezmoi. Условные блоки по `.profile`:
```
{{ if eq .profile "personal" -}}
Host github.com
  IdentityFile ~/.ssh/id_ed25519_personal
{{- end }}

{{ if eq .profile "work" -}}
Host work-gitlab.internal
  IdentityFile ~/.ssh/id_ed25519_work
{{- end }}
```

**Bitwarden item per ключ:**
```
Item: dotforge-ssh-personal
  Attachments:
    - id_ed25519_personal
    - id_ed25519_personal.pub
  Custom fields:
    - profile:        personal
    - created_at:     2026-05-01
    - created_on:     MacBook-Pro-Personal.local
    - fingerprint:    SHA256:xK9aB7c...
    - algorithm:      ed25519
    - comment:        roman@personal-macbook-pro-2026-05-01
```

**Манифест в репо** — `ssh/manifest.yaml`:
```yaml
keys:
  - name: id_ed25519_personal
    profile: personal
    bitwarden_item: dotforge-ssh-personal
    fingerprint: SHA256:xK9aB7c...
    public_key: ssh-ed25519 AAAA... roman@personal-macbook-pro-2026-05-01
    created_at: 2026-05-01
    created_on: MacBook-Pro-Personal.local
    used_on:
      - MacBook-Pro-Personal.local
      - MacBook-Air.local
    purpose: github + personal servers
```

Манифест публичен (только публичные ключи + метаданные). Doctor сверяет fingerprint на диске с записанным.

**Кто обновляет `used_on`:**
- На `dot apply` — после успешного восстановления ключа из Bitwarden хук добавляет текущий `hostname` в `used_on`, если ещё не там, и коммитит изменение в репо (auto-push в отдельной ветке `auto/used-on-updates` для безопасности, либо в main с явным флагом `--auto-commit`).
- На `dot ssh new` / `dot ssh pull` — текущий хост сразу попадает в `used_on`.
- На `dot doctor` — если хост не в `used_on`, выводится подсказка "this machine isn't registered for this key — run `dot apply` to register".

### 4.7. Claude конфиг

В chezmoi:
```
chezmoi/dot_claude/
├── settings.json
├── CLAUDE.md
├── agents/
├── commands/
├── skills/
└── plugins/
```

Не переносятся:
- `~/.claude/projects/` — история чатов и кеш.
- `~/.claude/.credentials.json` — токен (логинится вручную).
- `~/.claude/statsig/`, `~/.claude/todos/` — runtime-кеш.

Применение через стандартный `chezmoi apply` — никаких отдельных хуков не нужно.

### 4.7.1. VSCode / Cursor расширения

Список расширений хранится в репо как plain text:
```
chezmoi/dot_config/Code/extensions.txt
chezmoi/dot_config/Cursor/extensions.txt
```

Каждый файл — вывод `code --list-extensions` (или `cursor --list-extensions`):
```
ms-python.python
dbaeumer.vscode-eslint
github.copilot
...
```

**Установка** — отдельный хук `run_onchange_70-install-vscode-extensions.sh.tmpl`, активный только если в архетипе/фичах есть `editor/vscode`:
```bash
while IFS= read -r ext; do
  code --install-extension "$ext" --force
done < ~/.config/Code/extensions.txt
```

**Снапшот** — `dot vscode sync` запускает `code --list-extensions > "$(chezmoi source-path)/dot_config/Code/extensions.txt"`, далее обычный `git diff` и коммит. Путь к репо разрешается через `chezmoi source-path` (по дефолту `~/.local/share/chezmoi`).

**Settings.json** — лежит в том же `chezmoi/dot_config/Code/User/settings.json`, синхронизируется как обычный дотфайл через chezmoi.

### 4.8. CLI `dot`

Тонкий bash-врапер вокруг chezmoi и хуков. Команды:

| Команда | Описание |
|---------|----------|
| `dot apply` | Применить состояние из репо к машине (= `chezmoi apply` + перезапуск нужных хуков). |
| `dot snapshot` | Захватить текущее состояние машины обратно в репо (Brewfile.dump, chezmoi re-add для изменённых файлов, обновление manifest). |
| `dot doctor` | Показать diff: дотфайлы (chezmoi diff), Brew (brew bundle check), macOS (defaults сравнение), SSH (fingerprint). |
| `dot pull <path>` | Втянуть один локальный файл/настройку в репо, в правильную профильную/архетипную папку. |
| `dot archetype list` | Список доступных архетипов. |
| `dot archetype show <name>` | Что войдёт + что унаследовано через `extends`. |
| `dot archetype switch <name>` | Сменить архетип машины с подтверждением diff'а (что добавится/удалится). |
| `dot feature toggle <name>` | Включить/выключить опциональную фичу. |
| `dot ssh list` | Печать `ssh/manifest.yaml` в человеческом виде. |
| `dot ssh new --profile <p> --purpose <text>` | Сгенерить новый ключ, залить в Bitwarden, обновить манифест. |
| `dot ssh pull <path>` | Втянуть существующий локальный ключ в Bitwarden + манифест. |
| `dot ssh doctor` | Сверка fingerprint'ов и `used_on`. |
| `dot ssh rotate <name>` | Сгенерить новый ключ, оставить старый как backup. |
| `dot ssh sync <name>` | Подтянуть ключ из Bitwarden поверх локального (используется когда `dot doctor` показал расхождение fingerprint'ов). |
| `dot brew cleanup` | Удалить пакеты, которые есть локально, но не в Brewfile (с подтверждением). |
| `dot macos add <domain> <key> --module <name>` | Захватить текущее значение macOS-default'а в указанный модуль (обходит ограничение автоснапшота). |
| `dot vscode sync` | Сохранить список расширений VSCode/Cursor в репо (`code --list-extensions` → файл). |

**Алгоритм `dot pull <path>`:**
1. Считать содержимое файла, посчитать diff с уже существующим состоянием в репо (если есть).
2. Спросить у пользователя:
   - **Profile-specific?** — `personal` / `work` / `shared` (default).
   - **Archetype-specific?** — `dev-machine` / `media` / ... / `всегда` (default).
   - **Auto-load?** — для shell-фрагментов: добавить ли source-line в `dot_zshrc.tmpl`. Для plist'ов: установить ли LaunchAgent.
3. Положить файл в `chezmoi source-path` через `chezmoi add` (с расширением `.tmpl` если выбраны условия).
4. Если выбраны условия — обернуть содержимое (или сам файл) в `{{ if eq .profile "..." }}...{{ end }}`.
5. Если требуется auto-load — модифицировать `dot_zshrc.tmpl` или соответствующий шаблон, добавив в правильный условный блок.
6. Показать `git diff`, не коммитить (пользователь ревьюит и коммитит сам).

**Размещение `dot` CLI.** Один источник: `chezmoi/dot_local/bin/executable_dot` (chezmoi-префикс `executable_` ставит +x). Никакого `bin/dot` в корне репо — это убирает дублирование. Минус — запустить `dot` из свежеклонированного репо до `chezmoi apply` нельзя; bootstrap всё равно работает напрямую с chezmoi, так что ОК.

**На bootstrap `dot` ещё нет** — bootstrap работает напрямую с chezmoi и хуками. После первого `apply` `dot` появляется в `~/.local/bin/` и доступен.

---

## 5. Раскладка репо

```
dotforge/
├── bootstrap.sh                    # точка входа
├── README.md
├── chezmoi/                         # source dir для chezmoi (всё, что попадает в $HOME)
│   ├── .chezmoi.toml.tmpl           # запрос данных при init (через --promptString)
│   ├── dot_zshrc.tmpl               # с условными блоками по profile/archetype
│   ├── dot_gitconfig.tmpl
│   ├── dot_ssh/
│   │   └── config.tmpl
│   ├── dot_claude/
│   │   ├── settings.json
│   │   ├── CLAUDE.md
│   │   ├── agents/
│   │   ├── commands/
│   │   ├── skills/
│   │   └── plugins/
│   ├── dot_config/
│   │   ├── shell/                   # фрагменты скриптов, source-ятся из dot_zshrc
│   │   │   ├── git-vpn-proxy.sh.tmpl     # work-only через {{ if eq .profile "work" }}
│   │   │   └── dev-aliases.sh.tmpl
│   │   └── Code/
│   │       └── extensions.txt       # список VSCode-расширений (см. 4.7.1)
│   ├── dot_local/bin/
│   │   └── executable_dot           # сам CLI (единственный источник)
│   ├── private_Library/LaunchAgents/
│   │   └── com.user.git-vpn-proxy.plist.tmpl   # work-only через шаблон
│   └── .chezmoiscripts/
│       ├── run_once_before_10-install-bw.sh
│       ├── run_onchange_20-apply-brewfiles.sh.tmpl
│       ├── run_onchange_30-apply-macos-defaults.sh.tmpl
│       ├── run_onchange_40-install-runtimes.sh.tmpl
│       ├── run_onchange_50-pull-ssh-keys.sh.tmpl
│       └── run_onchange_70-install-vscode-extensions.sh.tmpl
│
├── archetypes/
│   ├── minimal.yaml                 # корневой
│   ├── dev-machine.yaml             # extends: minimal
│   ├── media.yaml                   # extends: minimal
│   └── ops-server.yaml              # extends: minimal
│
├── Brewfile.minimal
├── Brewfile.dev-core
├── Brewfile.languages-toolchain
├── Brewfile.gui-dev-core
├── Brewfile.docker
├── Brewfile.jetbrains
├── Brewfile.llm
├── Brewfile.cursor
├── Brewfile.media
│
├── macos/
│   ├── _base.sh
│   ├── dev-defaults.sh
│   ├── media-defaults.sh
│   └── work-defaults.sh
│
├── runtimes/
│   ├── node.sh
│   ├── python.sh
│   ├── go.sh
│   ├── rust.sh
│   └── ollama-models.sh
│
├── ssh/
│   └── manifest.yaml                # публичные ключи + метаданные
│
└── lib/                             # общие bash-утилиты
    ├── log.sh                       # логирование/UX
    ├── secrets.sh                   # обёртки вокруг bw
    ├── archetype.sh                 # парсинг YAML, разрешение extends
    └── doctor.sh                    # сравнение состояний
```

---

## 6. Пользовательские флоу

### 6.1. Bootstrap новой машины

```
$ curl -fsSL https://raw.githubusercontent.com/romandubovik/dotforge/main/bootstrap.sh | bash

────── Bootstrap dotforge ──────

→ Installing Xcode Command Line Tools (~5 min, GUI dialog)…  ✓
→ Installing Homebrew…  ✓
→ Installing chezmoi, bw, yq, gum…  ✓

? Machine name (human-friendly): my-new-mac
? Profile:                  > personal     work
? Archetype:                > dev-machine  minimal  media  ops-server
? Optional features (Space — toggle, Enter — confirm):
  [x] local-llm
  [x] cursor-ide
  [ ] docker-desktop
  [ ] jetbrains

? Bitwarden email: ip.romandubovik@gmail.com
? Master password: ********

────── Applying ──────
[1/8] Brewfile.dev-core (+features)        ✓ 4m 12s
[2/8] Brewfile.languages-toolchain         ✓ 1m 30s
[3/8] Brewfile.gui-dev-core (+cursor,llm)  ✓ 8m 04s
[4/8] Dotfiles (chezmoi apply)             ✓
[5/8] macOS defaults (dev-defaults)        ✓
[6/8] Runtimes: fnm/pyenv/go/rust          ✓ 3m 50s
[7/8] Ollama models                        ✓ 2m 10s
[8/8] SSH keys from Bitwarden              ✓

✓ Done. Restart your shell.
```

### 6.2. Snapshot (захват эталона)

На текущей машине поставил новую программу или поправил `.zshrc`:

```
$ dot snapshot
─── Detecting changes ───────────────────────────────────
  + Brewfile: ripgrep-all (new)
  + Brewfile: jetbrains-toolbox (new)
  ~ ~/.zshrc (modified, 4 lines)
  ~ ~/.gitconfig (modified, 1 line)
  + ~/.config/git-vpn-proxy.sh (new file — will prompt for profile/load via dot pull)

─── Where to put new items? ─────────────────────────────
  Brewfile: ripgrep-all
    > Brewfile.dev-core (recommended)
      Brewfile.minimal
      [skip]

  Brewfile: jetbrains-toolbox
    > New feature 'jetbrains' in archetype dev-machine
      Brewfile.dev-core
      [skip]

✓ Updated 4 files in repo. Review with `git diff`.
```

### 6.3. Doctor (сравнение машины с репо)

```
$ dot doctor

─── Dotfiles (chezmoi) ────────────────────────────────────
  ~ ~/.zshrc                  modified locally (3 lines)
  + ~/.config/git-vpn-proxy.sh  exists locally, not in repo
  - ~/.gitconfig.work         in repo, missing locally

─── Homebrew ──────────────────────────────────────────────
  + jetbrains-toolbox         unmanaged (installed locally, not in any Brewfile)
                              → `dot pull jetbrains-toolbox` to track in repo,
                                or enable feature `jetbrains` in this archetype.
  - htop                      missing (in Brewfile.dev-core, not installed)
                              → `dot apply` will install.

─── macOS defaults ────────────────────────────────────────
  ~ com.apple.dock tilesize    repo: 48, local: 64

─── SSH ───────────────────────────────────────────────────
  ! ~/.ssh/id_ed25519_personal
      local fingerprint:  SHA256:Ab12...
      manifest entry:     SHA256:xK9a... (created 2026-05-01)
      → keys differ! use `dot ssh sync` to investigate

  + ~/.ssh/id_legacy          exists locally, not in manifest

─── Archetype ────────────────────────────────────────────
  Profile:   personal
  Archetype: dev-machine
  Features:  [local-llm, cursor-ide]
  Required Brewfiles: all packages installed (1 unmanaged extra above).
  Required dotfile_modules: all present.
  Required runtimes: all installed.

Suggested next steps:
  • dot pull ~/.config/git-vpn-proxy.sh   (втянуть в репо)
  • dot snapshot                          (зафиксировать всё разом)
  • dot apply                             (накатить состояние из репо)
```

### 6.4. Pull одного файла

```
$ dot pull ~/.config/git-vpn-proxy.sh
? Profile-specific?   > work    (default: shared)
? Archetype-specific? > всегда  (default)
? How should this file load?
    > LaunchAgent (auto-start at login)
      Source from .zshrc
      No auto-load (just place file)

✓ Added chezmoi/dot_local/bin/executable_git-vpn-proxy.sh
    (wrapped in {{ if eq .profile "work" }})
✓ Added chezmoi/private_Library/LaunchAgents/com.user.git-vpn-proxy.plist.tmpl
    (wrapped in {{ if eq .profile "work" }})

git diff to review.
```

Если бы пользователь выбрал "Source from .zshrc" — был бы добавлен только сам скрипт + строчка `source ~/.local/bin/git-vpn-proxy.sh` в условный work-блок `dot_zshrc.tmpl`, без LaunchAgent.

### 6.5. Смена архетипа

```
$ dot archetype switch media

This will:
  + Install Brewfile.media (12 packages: davinci-resolve, ...)
  - Disable dotfile_modules: shell/dev-aliases, editor/vscode
  - Disable runtimes: node, python, go, rust
  ~ macOS: remove dev-defaults, apply media-defaults

Available for cleanup (NOT removed by default):
  • Brewfile.dev-core: ripgrep, fzf, gh, lazygit, ... (47 packages)
  Run with `--cleanup` to remove them.

Apply? [y/N]
```

С флагом `--cleanup`:
```
$ dot archetype switch media --cleanup
This will (additionally):
  - Uninstall: ripgrep, fzf, gh, lazygit, ... (47 packages)
Confirm cleanup? [y/N]
```

### 6.6. Создать новый SSH-ключ

```
$ dot ssh new --profile work --purpose "AWS bastion access"
✓ Generated id_ed25519_work_aws_bastion (ed25519)
  Comment: roman@work-macbook-2026-05-01-aws-bastion
  Fingerprint: SHA256:p3Qm...
✓ Uploaded to Bitwarden as `dotforge-ssh-work-aws-bastion`
✓ Added entry to ssh/manifest.yaml
✓ Added stub to ~/.ssh/config

To add to a server:
  ssh-copy-id -i ~/.ssh/id_ed25519_work_aws_bastion.pub user@host
```

---

## 7. Безопасность

- **В git нет ничего чувствительного.** Репо публичный — содержит только код, конфиги, публичные ключи, BW item IDs (не секретны).
- **Секреты только в Bitwarden.** Доступ через `bw` CLI, мастер-пароль вводится один раз за сессию.
- **SSH-ключи** — `chmod 600` для приватных, `chmod 644` для публичных. Хук проверяет права после копирования.
- **Bootstrap-скрипт** — стандартное предупреждение про `curl | bash`. Можно перед запуском прочитать (это публичный репо), либо клонировать руками и запустить локально.
- **Bitwarden master password** — не хранится. На каждой сессии запрашивается заново. После хуков `bw lock` (явно).

---

## 8. Идемпотентность и обратимость

- **Все шаги идемпотентны.** Bootstrap проверяет наличие Xcode CLT, Homebrew, chezmoi, bw перед установкой.
- **`brew bundle install`** — нативно идемпотентен.
- **chezmoi `apply`** — нативно идемпотентен. Файлы, которые больше не рендерятся (например, после смены архетипа), удаляются автоматически.
- **macOS defaults** — `defaults write` идемпотентен.
- **Runtime-установщики** проверяют `command -v` перед действием.
- **Откат:** `dot archetype switch <other>` явно перенацеливает машину на любой архетип с показом diff'а перед применением. Истории/undo нет — пользователь сам выбирает желаемое состояние. Полный откат до чистого Mac — задача переустановки macOS, не в скоупе.

---

## 9. Открытые вопросы и будущая работа

1. **Mas (Mac App Store)** — некоторые приложения только в App Store (Xcode, Things, и т.п.). `mas` CLI требует логина в App Store. На bootstrap пропускаем `mas` блоки если не залогинен; добавить в README инструкцию.
2. **Domain `dotforge.romandubovik.dev`** — опциональный шорт-URL для bootstrap. Без него работает прямой URL на raw.githubusercontent.com. Решение откладываем.
3. **CI на репо** — линтер для archetype YAML, проверка валидности Brewfile, тест bootstrap в Docker (если есть macOS runner). Откладываем.
4. **Локальные `.env` рабочих проектов** — упомянуты пользователем как возможный кейс. Если будут — добавятся как Bitwarden attachments + хук, который кладёт их в `~/work/<project>/.env`. Пока scope не уточнён.
5. **Auto-commit `used_on` в манифесте** — нужно ли требовать ручной коммит, или пушить в специальную ветку автоматически? Отложено, по умолчанию первая итерация делает локальный коммит без push.

---

## 10. Принятые решения

| Решение | Вариант | Обоснование |
|---------|---------|-------------|
| Хранение конфигов | Публичный GitHub-репо | Простой bootstrap, нет секретов в репо |
| Хранение секретов | Bitwarden | Уже используется пользователем, есть CLI |
| Tool stack | chezmoi + Brewfile + bash CLI | Стандарт, малый порог входа, гибкий |
| Multi-machine модель | profile + archetype + features | Покрывает personal/work без копипасты |
| GPG | Не используется | Подпись коммитов не настроена |
| Claude credentials | Логин руками | Избегаем работы с keychain |
| SSH naming | Суффикс по профилю (`id_ed25519_personal`) | Избегает коллизии между маками |
| SSH manifest | Публичный YAML в репо | Аудит без открытия Bitwarden |
| Termius | Не bootstrap-ится через CLI | Поставится как cask, синхронизируется через свой аккаунт |
