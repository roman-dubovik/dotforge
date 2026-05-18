# Design: Slice 2e (programmatic feature toggles) + Plan 3 MVP (multi-machine detect & resolve)
Date: 2026-05-18

## Goal

Closing-tails две задачи из ROADMAP "What's next":

- **Slice 2e** — программные toggles фич без редактирования chezmoi.toml: `dot apply --enable=docker_desktop --disable=office_suite`. Состояние персистится в отдельном state-файле `~/.config/dotforge/state.toml` (НЕ внутри chezmoi.toml, чтобы развязать CLI и chezmoi-шаблоны). `bootstrap.sh customize` дефолтит из state-файла если он есть; `chezmoi.toml.tmpl` читает state-файл и оверрайдит `[data.features]`.

- **Plan 3 MVP** — non-destructive detection + manual resolution в `dot pull`. Новые флаги `--resolve=ours|theirs|interactive|abort`; новый subcommand `dot status` (read-only: что разошлось локально и относительно remote). Полноценный three-way merge — OUT of scope для MVP.

Целевая ветка: `develop` (создаётся из `main` в начале сессии). Merge develop → main — отдельным шагом, по команде пользователя.

## Branch strategy

```
main (current)
 └── develop (new)
       ├── feature/slice-2e        (Task 1, branches off develop)
       └── feature/plan3-reconcile (Task 2, branches off develop AFTER Task 1 merge)
```

Task 1 → develop → Task 2 → develop. Никакого параллельного исполнения: оба касаются `executable_dot`, `README.md`, `CHANGELOG.md`, `ROADMAP.md`.

## File-touch matrix

| Task | Files | Touches |
|------|-------|---------|
| **1 — Slice 2e** | `scripts/lib/state.sh` | NEW — TOML read/write helpers для state.toml |
| | `scripts/dot-apply.sh` | modify — добавить парсинг `--enable=` / `--disable=` |
| | `scripts/dot-features.sh` | NEW — listing + источник значений |
| | `chezmoi/.chezmoi.toml.tmpl` | modify — читать state.toml через `joinPath`/`stat`/`readFile` и оверрайдить `[data.features]` если present |
| | `chezmoi/dot_local/bin/executable_dot` | modify — route `features` subcommand, update help |
| | `bootstrap.sh` (`cmd_customize`) | modify — defaults из state.toml если файл существует |
| | `scripts/customize-brewfile.sh` | (только если customize пишет state) — пишет в state.toml через `lib/state.sh` |
| | `tests/lib/state.bats` | NEW |
| | `tests/scripts/dot-apply-features.bats` | NEW |
| | `tests/scripts/dot-features.bats` | NEW |
| | `README.md` | modify — раздел про `--enable/--disable`, `dot features` |
| | `CHANGELOG.md` | modify — Unreleased секция |
| | `ROADMAP.md` | modify — Slice 2e → Shipped |
| **2 — Plan 3 MVP** | `scripts/dot-status.sh` | NEW — non-destructive divergence report |
| | `scripts/dot-pull.sh` | modify — `--resolve=ours\|theirs\|interactive\|abort` (default abort = текущее поведение) |
| | `scripts/lib/git-state.sh` | NEW (optional) — helpers: stash/pop, divergence detect |
| | `chezmoi/dot_local/bin/executable_dot` | modify — route `status` subcommand, обновить help |
| | `tests/scripts/dot-status.bats` | NEW |
| | `tests/scripts/dot-pull-resolve.bats` | NEW |
| | `README.md` | modify — раздел про `dot status`, `dot pull --resolve` |
| | `CHANGELOG.md` | modify — Unreleased секция |
| | `ROADMAP.md` | modify — Plan 3 (MVP) → Shipped, polный three-way → отдельный пункт |

**Конфликт по файлам** (`executable_dot`, README/CHANGELOG/ROADMAP) разрешается **последовательным исполнением** (Task 1 mergе до Task 2 dispatch).

## Patterns to follow

- Flag-parsing — копировать `case`-pattern из `scripts/dot-apply.sh:28-57` (`--dry-run` / unknown→exit 2).
- bats-тесты — по образцу `tests/scripts/dot-apply-extract.bats` (sourced helpers, `BATS_TEST_TMPDIR`).
- Logging — через `lib/log.sh` (`info`, `ok`, `warn`, `error`, `section`).
- Shellcheck — все новые `.sh` файлы должны проходить `shellcheck` без warnings.
- Bash 3.2 совместимость (macOS дефолт).

## TOML state.toml — формат

```toml
# ~/.config/dotforge/state.toml
# Managed by `dot apply --enable=...` and `bootstrap.sh customize`.
# Manual edits allowed but will be overwritten on next CLI call.
[features]
docker_desktop = true
ai_assistants  = true
vpn_suite      = true
office_suite   = false
media_tools    = true
design_tools   = true
```

**Mutation API (`scripts/lib/state.sh`):**

```bash
state_init                          # creates ~/.config/dotforge/state.toml with defaults if missing
state_get features.docker_desktop   # → "true" / "false"
state_set features.docker_desktop true   # in-place atomic write (tmp+mv)
state_list_features                 # → "docker_desktop=true\nai_assistants=true\n..."
```

Реализация TOML-чтения/записи через `grep`/`sed`/`awk` (bash 3.2 compatible, без зависимостей). Только плоская `[features]` секция — без вложенных таблиц/массивов.

## chezmoi.toml.tmpl integration

Добавить в начало шаблона блок (псевдокод):

```go-template
{{- $stateFile := joinPath .chezmoi.homeDir ".config/dotforge/state.toml" -}}
{{- $stateExists := stat $stateFile -}}

# Each feature: prefer state.toml value if it exists, else prompt
{{- $docker := promptBoolOnce . "features.docker_desktop" "..." true -}}
{{- if $stateExists -}}
  {{- $stateContent := include $stateFile -}}
  # parse and override $docker (regex match in $stateContent)
{{- end -}}
```

**Простой вариант** (предпочтительный): `chezmoi.toml.tmpl` оставляем как есть с `promptBoolOnce`; state.toml служит только для `dot apply --enable/--disable` и `bootstrap customize` defaults. То есть state-файл = единственный source of truth ТОЛЬКО когда `--enable/--disable` явно вызвано; chezmoi promptBool-state продолжает работать самостоятельно. При расхождении: `dot features` показывает оба источника и предупреждает.

**Решение в пользу простого варианта** (избегаем go-template сложности и race-conditions с chezmoi data init):
- state.toml — только для CLI mutations
- chezmoi.toml.tmpl остаётся прежним
- `dot apply --enable=X` пишет в state.toml И вызывает `chezmoi set` (или прямой `sed` по `~/.local/share/chezmoi/chezmoi.toml`) для синхронизации
- `dot features` показывает: state.toml value, chezmoi.toml value, статус (in-sync / divergent)

## Plan 3 — `dot pull --resolve` semantics

```
dot pull [--resolve=MODE]

MODES (default: abort):
  abort         — текущее поведение: ff-only, выйти с ошибкой если non-ff
  ours          — git stash → ff-merge → если конфликт: git checkout --ours <file> → continue → stash pop
  theirs        — git stash → ff-merge → если конфликт: git checkout --theirs <file> → continue → stash pop
  interactive   — show divergence, ask per-file (gum confirm "keep local?" / "take remote?" / "abort")

ON ABORT (любая ошибка): restore stash, exit 1, log файлы которые остались в неконсистентном состоянии.
```

`dot status` — read-only:

```
$ dot status
remote: origin/main
local commits ahead: 2 (snapshot: hostname-mbp 2026-05-18, snapshot: hostname-mbp 2026-05-17)
local commits behind: 1 (feat: bump brewfile_archetype default)
working tree: clean
uncommitted scan outputs: none
chezmoi state: 3 files differ from declared (dot doctor: WARN)
```

Exit code: 0 if clean and in-sync; 1 if any divergence detected.

## External constraints

- Все `chezmoi git -- ...` команды работают в `~/.local/share/chezmoi/` (НЕ в `~/dotforge/`).
- macOS Bash 3.2 (нет `mapfile`, `${var^^}`, associative arrays).
- Никаких новых runtime-зависимостей (никакого `tomlq`/`dasel`). Только awk/grep/sed.
- `gum` уже есть в зависимостях (bootstrap проверяет) — можно использовать для `interactive` mode.
- Все хуки/коммиты — без `--no-verify` и без `Co-Authored-By`.

## Acceptance Criteria

### Task 1 — Slice 2e

1. **state.toml lifecycle**: первый запуск `dot apply --enable=docker_desktop` на машине без `~/.config/dotforge/state.toml` создаёт файл с **всеми шестью** флагами с дефолтными значениями (что в `.chezmoi.toml.tmpl`), затем выставляет `docker_desktop = true`.
2. **CLI mutation**: `dot apply --disable=office_suite,media_tools --enable=docker_desktop` корректно парсит CSV-список ИЛИ повторяющиеся флаги; обновляет state.toml; вызывает `chezmoi apply`. Файл TOML после операции синтаксически валиден.
3. **Unknown feature**: `dot apply --enable=nonexistent_flag` → exit 2 с сообщением "unknown feature: nonexistent_flag (valid: docker_desktop, ai_assistants, vpn_suite, office_suite, media_tools, design_tools)".
4. **`dot features` listing**: показывает все 6 флагов с текущими значениями + статус источника (`state.toml` / `chezmoi.toml` / `default`). Exit code 0.
5. **bootstrap customize defaults**: `bootstrap.sh customize` на машине с существующим state.toml дефолтит чекбоксы в `gum choose` из state.toml значений (а не из chezmoi.toml).
6. **chezmoi sync**: после `dot apply --enable=X` запуск `chezmoi data | jq .features.X` возвращает `true` (значение реально применилось в chezmoi).
7. **Тесты**: bats unit для `lib/state.sh` (get/set/list/init) + integration для `dot apply --enable/--disable` (mock chezmoi) + `dot features`. Все проходят `bats tests/`.
8. **Shellcheck**: все новые/изменённые `.sh` — без warnings.
9. **Docs**: README раздел `Feature flags` обновлён, CHANGELOG Unreleased, ROADMAP `Slice 2e` → Shipped.

### Task 2 — Plan 3 MVP

1. **`dot status` non-destructive**: команда не выполняет fetch/pull/stash/apply без явного флага `--fetch`; читает текущее состояние локально + (опционально) `chezmoi git -- fetch` если `--fetch`.
2. **`dot status` output**: показывает (a) ahead/behind по origin/<branch>, (b) clean/dirty working tree, (c) список uncommitted scanner outputs, (d) `dot doctor` summary (PASS/WARN/FAIL count). Exit 0 если everything in-sync, 1 если хоть одна дивергенция.
3. **`dot pull --resolve=abort`** (default) — поведение **байт-в-байт идентично** текущему `dot pull` (regression test against current implementation).
4. **`dot pull --resolve=ours` happy path**: на машине с локальным uncommitted scanner output + remote с новым коммитом → stash → ff-merge → stash pop без конфликтов → `chezmoi apply` → exit 0. Локальный uncommitted output сохранён.
5. **`dot pull --resolve=ours` conflict path**: тот же сценарий, но conflict на pop → автоматический `git checkout --ours <file>` → continue → exit 0 (locally-modified files preserved).
6. **`dot pull --resolve=theirs`**: симметрично ours, но `git checkout --theirs`.
7. **`dot pull --resolve=interactive`**: при конфликте — `gum confirm "<file>: keep local? (y/n)"` per-file; n → take remote. Без `gum` (e.g. в bats) — fallback на `read -p`.
8. **`dot pull --resolve=<invalid>`**: exit 2 с listing допустимых modes.
9. **Recovery on failure**: любая ошибка в `--resolve=ours/theirs/interactive` → `git stash pop` восстанавливает локальные изменения; пользователь увидит explicit "stash restored, resolve manually" message.
10. **Тесты**: bats для `dot status` (clean / ahead / behind / dirty) + integration для каждого `--resolve` mode (используя temp git repo как фикстуру). Все проходят.
11. **Shellcheck**: все новые/изменённые `.sh` — без warnings.
12. **Docs**: README раздел про `dot pull --resolve` + `dot status`, CHANGELOG, ROADMAP.

## Open questions

1. **chezmoi sync mechanism в Slice 2e** — оптимальный путь записи в `~/.local/share/chezmoi/chezmoi.toml`:
   - (a) `sed` в-плейс по `[data.features]` секции — простой, но хрупкий к форматированию
   - (b) `chezmoi state` API — поддерживает только set-default-value, не overwrite
   - (c) regenerate всю секцию из state.toml — самый предсказуемый
   - **Решение**: (c) — implementer выбирает реализацию, AC проверяет результат.

2. **`scripts/customize-brewfile.sh` integration** — текущий код пишет только в Brewfile.local, не в chezmoi.toml. Расширяем ли его на state.toml в этой же сессии или оставляем как-есть (bootstrap.sh customize вызывает `dot apply --enable=...` пачкой)?
   - **Решение**: оставляем customize-brewfile.sh как есть; bootstrap.sh customize теперь после обновления Brewfile.local вызывает `dot apply --enable=A,B --disable=C,D` для синхронизации state.toml.

3. **`dot status --fetch` semantics** — если `--fetch` указан, делаем `chezmoi git -- fetch` перед anchoring divergence; если нет — используем уже-зафетченный `origin/<branch>` ref. **Решение**: default = no fetch (offline-safe); `--fetch` явный opt-in.
