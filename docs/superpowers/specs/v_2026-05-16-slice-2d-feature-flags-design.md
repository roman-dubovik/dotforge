# Design: slice 2d — Feature flags + deferred items (macOS capture, bats tests)
Date: 2026-05-16
Predecessors: slices 1+2a+2b+2c (all shipped 2026-05-16)
Status: READY TO EXECUTE (Phase 2.5 brief pending)

## Goal

Закрыть две ортогональные оси сверх архетипов:
1. **Feature flags** — fine-grained toggle конкретных пакетов поверх archetype-выбора секций. Пользователь хочет `minimal-dev` НО с `docker-desktop` ИЛИ `full` НО без `office`. Реализация: `[data.features]` map в chezmoi, `customize-brewfile.sh --enable=X --disable=Y` (Option B — Brewfile стаёт plain), `dot apply --enable/--disable` + bootstrap customize menu для UX.
2. **Deferred из slice 2c:** macOS capture в `dot snapshot` (нужен refactor `run_onchange_60` на файловый baseline) + bats-тесты для `extract_status_labels` (latent bug protection).

## Scope decisions (Phase 0)

1. **Storage shape:** `[data.features]` map (`docker_desktop = true`). Чистый namespace, `{{ if .features.docker_desktop }}` синтаксис в шаблонах.
2. **Integration mechanism:** **Option B** — `customize-brewfile.sh --enable=X --disable=Y` filters поверх archetype's section selection. Brewfile стаёт plain (без markers). Feature → package list hardcoded map в customize-brewfile.sh.
3. **Toggle UX:** **only bootstrap.sh customize menu в slice 2d** (gum-checkbox). `dot apply --enable=X --disable=Y` **отложен в slice 2e** — sed-edit пользовательского `~/.config/chezmoi/chezmoi.toml` слишком хрупкий (custom modifications, missing sections, comments) и заслуживает отдельного слайса с правильной реализацией через `chezmoi data` API или structural-edit tool. Bootstrap menu даёт полноценный UX для toggles в этой версии.
4. **macOS capture:** baseline переезжает в `chezmoi/dot_config/dotforge/macos-defaults.txt`. scan-macos получает `--capture`; `run_onchange_60` переписывается на чтение из файла.
5. **Bats tests:** только для `extract_status_labels` (pure function); тестовый файл `tests/scripts/dot-apply-extract.bats`.

## Initial feature set (6 toggles)

Маппинг feature → конкретные пакеты в Brewfile (hardcoded в customize-brewfile.sh). Defaults подобраны так, что нулевая конфигурация = поведение текущего Brewfile:

| Feature | Default | Brewfile lines controlled |
|---------|---------|--------------------------|
| `docker_desktop` | true | `cask "docker-desktop"` |
| `ai_assistants` | true | `cask "claude"`, `cask "chatgpt"` |
| `vpn_suite` | true | `cask "tunnelblick"`, `cask "amneziavpn"`, `cask "anydesk"`, `cask "displaylink"`, `cask "termius"`, `cask "windows-app"` |
| `office_suite` | false | `mas "Microsoft Word"`, `mas "Microsoft Excel"`, `mas "Microsoft PowerPoint"` |
| `media_tools` | true | `brew "ffmpeg"`, `brew "yt-dlp"`, `brew "pandoc"`, `brew "tectonic"` |
| `design_tools` | true | `cask "drawio"` |

`office_suite` = false по умолчанию: лицензия MAS требует Apple ID. `local_llm` отложен в 2e — ollama пока не в Brewfile, а dead-config feature flag без эффекта не имеет смысла.

## File-touch matrix

| Task | Files | Touches | Complexity | Model |
|------|-------|---------|------------|-------|
| A | `chezmoi/.chezmoi.toml.tmpl` | add `[data.features]` block с `promptBoolOnce` для 6 toggles | Simple | Haiku |
| B | `scripts/customize-brewfile.sh` | + `--enable=`/`--disable=` flags; hardcoded feature→regex map; post-section filter | Medium | Sonnet |
| C | `chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl` | update version hash to include features; pass features to customize-brewfile | Simple | Haiku |
| E | `bootstrap.sh` (или `scripts/customize-brewfile.sh` interactive path) | + customize-flow extension с feature gum-checkbox menu | Medium | Sonnet |
| F | `scripts/scan-macos-defaults.sh` | + `--capture` mode пишет `chezmoi/dot_config/dotforge/macos-defaults.txt` | Medium | Sonnet |
| G | `chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh` | refactor: read from `macos-defaults.txt` instead of hardcoded baseline | Medium | Sonnet |
| H | `scripts/dot-snapshot.sh` | + scan-macos invocation (no longer `--no-macos` placeholder) | Simple | Haiku |
| I-prep | `lib/dot-apply-helpers.sh` (NEW), `scripts/dot-apply.sh` (source it) | Extract `extract_status_labels` into lib for shared sourcing | Simple | Haiku |
| I | `tests/scripts/dot-apply-extract.bats` (NEW) | bats тесты, sources `lib/dot-apply-helpers.sh` | Simple | Haiku |
| J | `README.md`, `docs/usage.md` | feature list, snapshot теперь полный | Simple | Sonnet |

**~~D~~ (`dot apply --enable/--disable`)** — отложено в slice 2e. Toggle UX в 2d покрыт через Task E (bootstrap menu).

**Conflict analysis:** все 9 задач трогают disjoint files (I-prep делит scripts/dot-apply.sh с… ничем — только мы его трогаем). Sequential выполнение в одном worktree, ~9 commits.

**Dependencies:**
- A → C (hook references chezmoi data; A создаёт schema)
- B → E (E использует customize-brewfile interactive feature menu)
- F → G (G читает файл, F его создаёт)
- F → H (H запускает scan-macos --capture)
- I-prep → I (test sources lib helper)

## Patterns to follow

**Feature data shape (chezmoi.toml.tmpl):**
```toml
{{- $docker := promptBoolOnce . "features.docker_desktop" "Install Docker Desktop?" true -}}
{{- $ai := promptBoolOnce . "features.ai_assistants" "Install AI assistant casks (Claude, ChatGPT)?" true -}}
...
[data]
brewfile_archetype = {{ $archetype | quote }}

[data.features]
docker_desktop = {{ $docker }}
ai_assistants = {{ $ai }}
vpn_suite = {{ $vpn }}
office_suite = {{ $office }}
media_tools = {{ $media }}
design_tools = {{ $design }}
local_llm = {{ $llm }}
```

**Feature→packages map (customize-brewfile.sh) — bash 3.2 parallel arrays:**
```bash
# Parallel arrays: FEATURE_NAMES[i] ↔ FEATURE_PATTERNS[i]
FEATURE_NAMES=(
  "docker_desktop"
  "ai_assistants"
  "vpn_suite"
  ...
)
FEATURE_PATTERNS=(
  '^cask "docker-desktop"'
  '^cask "(claude|chatgpt)"'
  '^cask "(tunnelblick|amneziavpn|anydesk|displaylink|termius|windows-app)"'
  ...
)

apply_feature_filter() {
    local section_file="$1" feature_name action
    # Iterate enabled/disabled, grep -vE the patterns of disabled features
    ...
}
```

**Hook trigger via features (run_onchange_20):**
```bash
# version: brewfile-v4 {{ .profile }} features={{ .features | toJson | sha256sum | substr 0 8 }}
```
Chezmoi watches script-content-hash, так что любое изменение features → bump hash → re-run.

**macOS file format (macos-defaults.txt):**
```
# ── Dock ──
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
...
```
Прямые `defaults write` команды — hook их exec'ает в цикле. Lines starting with `#` — comments.

**Hook read pattern (run_onchange_60 after refactor) — следуем login-autostart pattern. NO `eval` (security):**
```bash
DEFAULTS_FILE="$REPO_ROOT/chezmoi/dot_config/dotforge/macos-defaults.txt"
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue   # skip comments
    [[ -z "${line// }" ]] && continue              # skip blank
    # Parse line into tokens; first must be "defaults", then call binary directly.
    # Captured file is trusted (user-owned), but eval would execute arbitrary code
    # if value contains backticks, $, ;, &&. Use read -ra to split safely.
    read -ra tokens <<<"$line"
    [[ "${tokens[0]}" == "defaults" ]] || { log_warn "skipping non-defaults line: $line"; continue; }
    defaults "${tokens[@]:1}"
done < "$DEFAULTS_FILE"
```

## Acceptance Criteria

### Task A — chezmoi.toml.tmpl `[data.features]`

A1. Шаблон содержит 6 `promptBoolOnce` calls для каждого toggle с defaults из таблицы выше.
A2. `[data.features]` блок генерируется в финальном `chezmoi.toml` с 6 bool полями.
A3. Существующий `brewfile_archetype` сохраняется без regression.
A4. **Non-TTY safety:** все `promptBoolOnce` имеют explicit defaults так, что `chezmoi apply` в non-interactive context (cron, CI, agent) не падает — defaults применяются без prompts. Smoke: `chezmoi apply` с stdin redirected from /dev/null проходит без TTY-error.
A5. Smoke: `chezmoi init --apply --promptBoolOnce features.docker_desktop=false ...` в test-режиме не падает; `chezmoi data` показывает корректную structure.

### Task B — customize-brewfile.sh feature filter

B1. Новые CLI флаги: `--enable=<feature>` (repeatable), `--disable=<feature>` (repeatable). Unknown feature name → exit 2 с listing supported features.
B2. Hardcoded parallel arrays `FEATURE_NAMES[]` и `FEATURE_PATTERNS[]` (bash 3.2 compat) для 6 toggles.
B3. После section selection: для каждой `--disable=X` фичи — grep -vE pattern из всех selected lines. Для `--enable=X` (когда секция уже выбрана) — no-op (lines уже включены); когда секция НЕ выбрана архетипом, `--enable` добавляет matching lines из canonical Brewfile в output. Edge case: enabling features в `cli-server` archetype, где нужная секция вообще пропущена — добавление допустимо.
B4. `--help` секция расширена: list 7 features.
B5. Atomic write (mktemp + mv) сохраняется.
B6. `--non-interactive`: если запускается из hook'а — features передаются через CLI (не interactive). Existing archetype-only mode без `--enable/--disable` работает идентично (zero regression).
B7. Manual smoke: `bash scripts/customize-brewfile.sh --archetype full --disable=office_suite --disable=docker_desktop --output /tmp/Brewfile.test --no-install` создаёт корректный файл без office MAS lines и без docker-desktop cask.

### Task C — Hook run_onchange_20 update

C1. Version-hash comment теперь включает `features` data: `# version: brewfile-v4 {{ .profile }} features={{ ... }}`.
C2. Hook читает enabled/disabled features из `.features` и формирует `--enable=X --disable=Y` args для customize-brewfile.
C3. Backward compat: если `.features` отсутствует (старая конфигурация) — hook работает как раньше (archetype-only).
C4. Hook test: `chezmoi apply` после смены features → Brewfile.local регенерируется с правильной filterной.

### ~~Task D — `dot apply --enable/--disable`~~ — ОТЛОЖЕНО в slice 2e

Sed-edit пользовательского `~/.config/chezmoi/chezmoi.toml` слишком хрупкий (custom modifications, missing sections, comments, ordering). Безопасная реализация требует structural-edit через `chezmoi data` API (нет такой команды CLI) или внешний TOML parser — это материал отдельного слайса с собственным design pass. Toggle UX в 2d полностью покрывается через Task E (bootstrap menu).

### Task E — bootstrap customize menu

E1. Расширение `bootstrap.sh customize` (или соответствующей entry point): после archetype-выбора — gum-checkbox menu с 7 features, pre-selected по текущим chezmoi data.
E2. Result сохраняется в chezmoi data (через `chezmoi init --promptBoolOnce features.X=...` или прямую запись).
E3. После выбора — auto-trigger `customize-brewfile.sh` с правильными `--enable/--disable`.
E4. Gum fallback: если gum отсутствует — список features + `read -r -p` для каждой y/n.

### Task F — scan-macos-defaults `--capture`

F1. Новый флаг `--capture` пишет `chezmoi/dot_config/dotforge/macos-defaults.txt` в формате `defaults write <domain> <key> -<type> <value>` (один per line), с section headers `# ── <section> ──` comments.
F2. `--capture` итерирует existing BASELINE array (или читает current system state через `defaults read`) — формат вывода — exactly то, что hook сможет `eval` обратно.
F3. Backup `.bak` существующего файла перед перезаписью.
F4. Sort within section но preserve section ordering.
F5. Existing `--diff` без regression.
F6. Smoke: запуск `--capture` на current машине создаёт корректный файл; `diff` против предыдущей версии показывает только реальные изменения.

### Task G — Hook run_onchange_60 refactor

G1. Скрипт переписан: вместо ~59 hardcoded `defaults write` строк — цикл чтения из `$REPO_ROOT/chezmoi/dot_config/dotforge/macos-defaults.txt`.
G2. **NO `eval`** (security). Comments (`^#`) и пустые строки skip'ятся. Non-comment lines парсятся через `read -ra tokens <<<"$line"`; первый токен должен быть `defaults` (иначе warn + skip); затем `defaults "${tokens[@]:1}"` — вызов бинаря напрямую без shell expansion. Captured file user-owned, но `eval` исполнил бы arbitrary code если значение содержит backticks/`$`/`;`.
G3. Хук остаётся idempotent (defaults write одного и того же — no-op).
G4. Хук остаётся trigger-on-content-change через `run_onchange_` префикс (hash скрипта = trigger).
G5. Backward compat: если `macos-defaults.txt` отсутствует — graceful warn + skip (не fail на свежей checkout до первого `dot snapshot`).
G6. Скрипт сокращается со 110 LoC до ~70 LoC.

### Task H — dot-snapshot включает macOS

H1. `--no-macos` больше не no-op — теперь это реальный opt-out из scan-macos --capture.
H2. По умолчанию: scan-cli + scan-login + scan-macos (3 scanners).
H3. log_step counters обновлены: `1/3`, `2/3`, `3/3`.
H4. Captured files list расширен `chezmoi/dot_config/dotforge/macos-defaults.txt`.
H5. Smoke: `dot snapshot --help` показывает обновлённый список scanners; `dot snapshot --no-macos --no-cli` запускает только login-autostart.

### Task I-prep — Extract helpers into lib

Iprep1. Создать `lib/dot-apply-helpers.sh` — содержит ТОЛЬКО функцию `extract_status_labels` (и/или другие pure helpers `lookup_before`/`lookup_after` если уместно отдельно).
Iprep2. `scripts/dot-apply.sh` — заменить inline definition на `source "$REPO_ROOT/lib/dot-apply-helpers.sh"`.
Iprep3. Behavior preserved — все unit + e2e тесты dot-apply из 2c (smoke `--dry-run` + `--help`) проходят без изменений.
Iprep4. shellcheck PASS на обоих файлах.

### Task I — bats tests for extract_status_labels

I1. NEW файл `tests/scripts/dot-apply-extract.bats` с 6 тест-кейсами:
  - single-word label ("Brewfile")
  - multi-word label ("chezmoi state")
  - all three statuses (OK/WARN/FAIL)
  - label exactly 22 chars (edge)
  - file with no status lines (empty output)
  - file missing (function should error gracefully; test verifies error)
I2. **Setup:** `source "$BATS_TEST_DIRNAME/../../lib/dot-apply-helpers.sh"` — clean import, NOT inline sed extraction (требует Task I-prep сначала).
I3. Tests run: `bats tests/scripts/dot-apply-extract.bats` — all green.
I4. Recommended bats install (Brewfile уже включает `bats-core`).

### Task J — Docs

J1. README.md: краткая feature list в subcommands-table (`dot apply --enable=X --disable=Y`).
J2. docs/usage.md: новая секция `### Feature flags` с:
  - Список 7 features + defaults + что они контролируют
  - 3 примера usage (`dot apply --enable=docker_desktop`, bootstrap menu, чтение через `chezmoi data`)
  - Edge cases (что делать если хочется feature вне archetype)
J3. Обновить `## dot CLI` section: snapshot теперь полный (3 scanners).
J4. Mandatory `git diff` paste агентом для proof-of-landing.

## NOT in scope

- Feature flags для других dimensions (LaunchAgents, macOS keys, SSH/git) — отдельный слайс 2e+.
- More than 7 initial toggles — расширяемо позже без breaking change.
- Templated Brewfile.tmpl (Option A) — не выбрано пользователем.
- Section markers в Brewfile (Option C) — не выбрано пользователем.
- Migration tool для пользователей с custom Brewfile.local — пусть остаются on Brewfile.local, features применяются только когда regenerate from archetype.

## Risks / open questions

- **`dot apply --enable=X` modifies chezmoi.toml** — это inverted: обычно chezmoi.toml редактируется пользователем, а `dot apply` его читает. Если пользователь имеет custom modifications в chezmoi.toml, наш sed-edit может сломать структуру. Mitigation: проверка структуры перед edit; warn если sections выглядят custom; fallback to instruction.
- **`gum` отсутствует** в bootstrap customize menu — fallback на `read -p` цикл. Уже паттерн в проекте.
- **`local_llm` feature без packages** — пока no-op (заготовка). Документировать как "coming with ollama integration".
- **chezmoi promptBoolOnce при `chezmoi init` non-TTY** — known issue. Defaults обеспечивают что chezmoi apply работает; но первичный init требует interactive OR `chezmoi init --promptBoolOnce features.X=true` явно.

## Execution flow

Single worktree, sequential commits (9 commits, after dropping D):

```
git worktree add .claude/worktrees/slice-2d -b feature/slice-2d-feature-flags main
# 1. Task A: feat(chezmoi): add [data.features] block with 6 toggles
# 2. Task B: feat(brewfile): add --enable/--disable feature filter to customize-brewfile
# 3. Task C: feat(chezmoi): include features in run_onchange_20 trigger hash
# 4. Task F: feat(scan): add --capture mode to scan-macos-defaults
# 5. Task G: refactor(chezmoi): read macos-defaults from file (no eval)
# 6. Task H: feat(dot): include macOS in dot snapshot
# 7. Task E: feat(bootstrap): add feature menu to customize flow
# 8. Task I-prep: refactor(dot): extract helpers to lib/dot-apply-helpers.sh
# 9. Task I: test(dot): add bats tests for extract_status_labels
# 10. Task J: docs: document feature flags + full dot snapshot
```

Порядок: foundation (A) → core (B, C) → deferred macOS (F, G, H) → UX (E) → tests-prep (I-prep, I) → docs (J).

После всех коммитов: Phase 4 shellcheck + bats → Phase 5 pr-review-toolkit (parallel: code-reviewer + silent-failure-hunter + pr-test-analyzer) → Phase 6 fix loop (rounds until 0 P0/P1, per skill update from 2c session) → Phase 7 merge + v_*-rename + memory update.
