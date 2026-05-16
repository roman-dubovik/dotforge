# Design: slice 2c — `dot apply` / `dot snapshot` / `dot pull`
Date: 2026-05-16
Predecessors: slice 1 (`dot doctor`), 2a (`dot` namespace), 2b (Brewfile archetypes) — all shipped
Status: READY TO EXECUTE (Phase 2.5 brief pending)

## Goal

Замкнуть петлю `diagnose → fix → verify` и `sync between machines` за один shell call. Сегодня для sync между Маками 4 шага вручную (`git pull && chezmoi apply && bootstrap.sh doctor && ...`). После 2c: `dot pull`. Аналогично `dot apply` показывает before/after drift одной командой, а `dot snapshot` капчурит текущее состояние машины в canonical-файлы + предлагает git commit.

## Scope decisions (Phase 0)

1. **`dot apply` before/after UX:** Cache `dot doctor` output в `/tmp/dot-doctor.before.<pid>`, после `chezmoi apply` запустить doctor повторно, показать diff конкретных строк (что починилось, что осталось).
2. **`dot snapshot` scanners:** scan-cli + scan-login-autostart (default ON), `--no-cli` / `--no-autostart` для opt-out. **macOS исключён из 2c** (требует переписывания `run_onchange_60-apply-macos-defaults.sh` — отдельный слайс).
3. **`dot snapshot` commit prompt:** per-file `gum confirm` (granularity предпочтительнее, snapshot редкая операция).
4. **`dot pull` failure mode:** strict bail-everywhere — любая ошибка на любом шаге (fetch/pull/apply) → exit с понятным сообщением. После apply doctor запускается всегда, его exit code = exit code команды.
5. **Selective apply (`--check=brewfile`):** OUT of scope (chezmoi не имеет фильтра, обходной путь раздул бы шим).
6. **`dot apply --dry-run`:** INCLUDE — тонкая обёртка над `chezmoi diff`.

## File-touch matrix

| Task | Files | Touches | Complexity | Model |
|------|-------|---------|------------|-------|
| A | `scripts/scan-login-autostart.sh` | + `--capture` mode пишет `login-items.txt` | Simple | Haiku |
| B | `scripts/dot-apply.sh` (NEW) | new file: cache doctor → chezmoi apply → diff | Medium | Sonnet |
| C | `scripts/dot-snapshot.sh` (NEW) | new file: scan-cli --capture + scan-login-autostart --capture + per-file gum confirm + git commit | Medium | Sonnet |
| D | `scripts/dot-pull.sh` (NEW) | new file: chezmoi git fetch/pull (ff-only под капотом, strict bail снаружи) + chezmoi apply + dot doctor | Medium | Sonnet |
| E | `chezmoi/dot_local/bin/executable_dot` | +3 case branches (apply/snapshot/pull) + help text update | Simple | Haiku |
| F | `README.md`, `docs/usage.md` | extend `## dot CLI` table + examples + roadmap update | Simple | Sonnet |

**Conflict analysis:** Tasks A, B, C, D, F touch disjoint files. Task E modifies `executable_dot` in a single block (apply/snapshot/pull cases inserted between `doctor)` and `version)`). Task A is a prerequisite of Task C. Therefore safe to **sequence in single worktree**: A → B → C → D → E → F.

## Patterns to follow

- **Dispatcher contract** (`executable_dot:31-77`):
  - `SUBCOMMAND="${1:-help}"`, then `shift || true`, then `case`.
  - For mutations: `bash "$REPO_ROOT/scripts/dot-<verb>.sh" "$@"` then `exit $?` (explicit forward).
  - For read-only: `exec bash ...` (auto-forward via exec).
- **Colors / logging:** Source `$REPO_ROOT/lib/log.sh` with fallback no-op stub (pattern at `scripts/scan-login-autostart.sh:15-19`). Use `log_section`, `log_ok`, `log_warn`, `log_error`, `log_step`.
- **Exit codes:** 0 success, 1 user-facing failure, 2 invalid argument. Doctor delta uses doctor's own exit code.
- **Error handling:** `set -euo pipefail` at top of every new script.
- **Argument parsing:** simple `while` loop with `case "$1"` per existing scripts (see `scan-cli.sh:80-120` for pattern).
- **`gum confirm`:** optional dependency. If `command -v gum` missing → fallback to `read -p` (yes/no). Pattern already in use elsewhere; verify before relying.

## External constraints

- Project is bash-only — no test framework (no `pnpm test`, no `npx jest`). Quality gates: `shellcheck` + manual smoke.
- All canonical files (Brewfile, cli-globals.txt, login-items.txt) live at repo root. Scripts must use `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` pattern.
- `chezmoi` is the source of truth for `~/.local/bin/dot`. The shim shipped at `chezmoi/dot_local/bin/executable_dot` is the working copy; testing requires `chezmoi apply` to deploy it OR direct `bash chezmoi/dot_local/bin/executable_dot ...` invocation.
- `$DOTFORGE_BRANCH` env var (default `main`) determines remote branch for `dot pull`.

## Acceptance Criteria

### Task A — scan-login-autostart `--capture`

A1. `scripts/scan-login-autostart.sh --capture` пишет текущий список Login Items в `$REPO_ROOT/login-items.txt` (one path per line; lex-sorted; LF endings).
A2. Existing flags (`--diff`, `--help`, default scan-mode) continue to work without regression.
A3. Если osascript блокирует доступ (System Settings → Automation) → exit 1 с понятной ошибкой, файл **не перезаписывается**.
A4. `--capture` бэкапит существующий `login-items.txt` в `.bak` (как scan-cli делает на `:153-155`).
A5. Manual smoke: запустить `--capture` на текущей машине, убедиться что diff против предыдущего `login-items.txt` пустой (если состояние не изменилось) или содержит ожидаемые строки.

### Task B — `scripts/dot-apply.sh`

B1. `dot apply` (без флагов): кэширует `bash $REPO_ROOT/scripts/doctor.sh --no-color > /tmp/dot-doctor.before.$$` (флаг для надёжности; TTY-detection на :45 doctor.sh уже strip'ает цвет при пайпе, `--no-color` — двойная защита), запускает `chezmoi apply`, после — повторно doctor → `.after.$$`, печатает delta-секцию (зелёное `✓` для строк где FAIL/WARN → OK, жёлтое для оставшихся WARN, красное для оставшихся FAIL).
B2. Exit code = exit code post-apply doctor (0 если after-state clean).
B3. `dot apply --dry-run`: вызывает `chezmoi diff` без mutate. `dot doctor` НЕ запускается. Exit code = `chezmoi diff` exit code.
B4. `dot apply --help` / `-h`: печатает usage block.
B5. `chezmoi apply` падение → bail с exit 1 и понятным сообщением; doctor delta не печатается (apply не состоялся).
B6. Tmp-файлы /tmp/dot-doctor.before.$$ / .after.$$ удаляются через `trap '... cleanup ...' EXIT`.
B7. Manual smoke: внести drift руками (e.g. `brew uninstall <packge>` или `rm ~/.config/foo`), `dot apply`, увидеть delta "1 WARN → 0 WARN".

### Task C — `scripts/dot-snapshot.sh`

C0. **Precondition guard:** в начале команды — `git -C $REPO_ROOT diff --cached --name-only`. Если non-empty → bail `[dot snapshot] repo has staged changes, commit or stash them first` (exit 1). Не должно быть silent bundling чужих staged-изменений в snapshot-коммит.
C1. По умолчанию: запускает `scan-cli --capture` + `scan-login-autostart --capture`. Прогресс через `log_step "1/2 scanning CLI globals..."` / `"2/2 scanning login items..."`.
C2. Флаги: `--no-cli` (skip scan-cli), `--no-autostart` (skip scan-login-autostart). Если оба указаны → error "nothing to snapshot".
C3. После сканеров: `git status --short -- <captured-files>`. Если изменений нет → "No changes captured." + exit 0.
C4. Если есть изменённые файлы: для каждого изменённого файла (`git diff` показывается inline сначала) — `gum confirm "Commit changes to <file>?"`. Yes → `git add <file>`. No → skip.
C5. После всех confirm'ов: если есть staged files → `gum input "Commit message:" --value "snapshot: <hostname> <YYYY-MM-DD>"`, затем `git commit -m "<msg>"`. Если нет staged → "No files staged. Aborting commit." + exit 0.
C6. **Без push** (auto-push не делается ни при каких условиях).
C7. `gum` отсутствует → fallback: `read -p "Commit changes to <file>? [y/N] "` + plain `read -p "Commit message: "`.
C8. macOS scanner НЕ запускается. `--no-macos` accepted as alias to no-op (для forward-compatibility).
C9. Manual smoke: установить какой-нибудь global package (e.g. `npm i -g cowsay`), `dot snapshot`, увидеть diff в `cli-globals.txt`, confirm → commit создан.

### Task D — `scripts/dot-pull.sh`

D1. Bail-everywhere: любая ошибка на любом шаге → exit 1 с message формата `[dot pull] <step> failed: <reason>`.
D2. Шаги (последовательно):
   1. `chezmoi git -- fetch origin "$DOTFORGE_BRANCH"` (default `main`)
   2. `chezmoi git -- pull --ff-only origin "$DOTFORGE_BRANCH"` — всегда; если up-to-date это no-op (git печатает "Already up to date.", exit 0). Если non-ff → git напечатает explicit error и exit non-zero → наш bail сработает естественно.
   3. `chezmoi apply`
   4. `dot doctor` (exit code = exit code команды)
D3. Apply + doctor запускаются всегда (даже если pull no-op) — safety net на случай локального drift.
D4. `dot pull --help` / `-h`: usage block.
D5. **No interactive confirmation** — операция тихая, всё через exit codes / log_section.
D6. Manual smoke: симулировать "behind" состояние (`git -C ~/.local/share/chezmoi reset --hard HEAD~1`), `dot pull`, убедиться что fast-forward сработал + apply + doctor.

### Task E — Dispatcher wiring

E1. В `chezmoi/dot_local/bin/executable_dot`: после ветки `doctor)` и до `version)` добавить три case-ветки `apply)`, `snapshot)`, `pull)`. Каждая использует `exec bash "$REPO_ROOT/scripts/dot-<verb>.sh" "$@"` — паттерн идентичный существующему `doctor)` (line 37), exit-code пропагируется автоматически.
E2. Help text (`help)` ветка) расширяется: новые subcommands добавлены в `Available commands:` секцию с одной строкой описания каждый.
E3. `dot --help` / `dot help apply` / `dot help snapshot` / `dot help pull` — top-level help перечисляет всё; per-command help делегируется (`exec bash ... --help`).
E4. Unknown subcommand → существующий fallback на exit 1.

### Task F — Documentation

F1. `README.md`:
   - Subcommands-table (около строк 23-38) расширяется: добавить строки для `dot apply`, `dot snapshot`, `dot pull` с одной фразой описания.
   - Roadmap-секция (около строк 60-65): убрать упоминание "slice 2c pending" — заменить на "shipped 2026-05-16".

F2. `docs/usage.md` (`## dot CLI` секция, строки 747-799):
   - Расширить subcommands-table: добавить 3 строки.
   - Help-output блок (строки 761-787): обновить с новым help text dispatcher'а.
   - Usage examples (строки 789-796): добавить 3 примера — `dot apply`, `dot apply --dry-run`, `dot snapshot`, `dot pull`. Каждый — 2-3 строки с показанным output.

F3. **Mandatory git-diff paste:** агент в отчёте обязан вставить `git diff README.md docs/usage.md` (stat достаточно если >100 строк). Пустой diff = провал.

## NOT in scope

- `dot apply --check=brewfile` (selective apply) — chezmoi не поддерживает, обходной путь раздул бы 2c.
- macOS-defaults в `dot snapshot` — требует переписать chezmoi-хук, отдельный слайс.
- Auto-push после `dot snapshot commit` — пользователь явно отверг.
- Multi-branch / non-`origin` remote в `dot pull` — только `origin $DOTFORGE_BRANCH`.
- Feature flags (slice 2d) — отдельный слайс.
- Unit tests (project is bash-only, нет тестового фреймворка) — verification = shellcheck + manual smoke.

## Risks / open questions

- **`gum` availability:** если `command -v gum` пуст в свежей системе — fallback на `read -p` работает, но UX deg. Текущий project уже использует gum (см. bootstrap.sh) → разумно требовать.
- ~~**Doctor delta robustness**~~ — **resolved (Phase 1):** doctor.sh has `--no-color` flag (`:32`) и TTY-detection (`:45`). Task B вызывает `doctor.sh --no-color` для capture → ANSI-strip не нужен.
- **chezmoi git -- pull** интерактивность: если remote требует auth (HTTPS+token) — может зависнуть. Acceptable — у пользователя SSH-ключи или git-credential-osxkeychain настроены. Документировать в Task F.
- **scan-login-autostart osascript permissions:** если script запускается через chezmoi run_onchange (cron-like), osascript может фейлить тихо. Capture запускается интерактивно из dot snapshot → должно работать. Документировать ограничение.

## Execution flow

Single worktree, sequential commits:

```
git worktree add .claude/worktrees/slice-2c -b feature/slice-2c-dot-loop main
# Каждая task — один commit в этом worktree:
# 1. Task A: feat(scan): add --capture mode to scan-login-autostart
# 2. Task B: feat(dot): add `dot apply` with before/after doctor diff
# 3. Task C: feat(dot): add `dot snapshot` (cli + autostart, per-file confirm)
# 4. Task D: feat(dot): add `dot pull` with strict bail
# 5. Task E: feat(dot): wire apply/snapshot/pull into dispatcher
# 6. Task F: docs: document new dot subcommands (apply/snapshot/pull)
```

После 6 коммитов: shellcheck → manual smoke → Phase 5 pr-review-toolkit (parallel) → Phase 6 fix loop → merge into main → rename plan to `v_*`.
