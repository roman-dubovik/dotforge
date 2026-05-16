# Slice 2c launch prompt: `dot apply` / `dot snapshot` / `dot pull`

Status: READY TO START
Date created: 2026-05-16
Predecessors: Plan 1, 1.5, 2 slices 1+2a+2b (all shipped)

## How to use this file

```
/team-lead docs/superpowers/specs/2026-05-16-slice-2c-dot-apply-snapshot-pull-prompt.md
```

The team-lead skill will read this prompt, run Phase 0 (likely needs `superpowers:brainstorming` for design decisions), then proceed through normal flow (Phase 1 → 2 → 2.5 brief → Phase 8 mode → 3 → verify → review → 9).

## Context

`dot` CLI namespace shipped in slice 2a with subcommands `doctor`, `help`, `version`. This slice adds the three "loop-closing" subcommands:

- **`dot apply`** — wrapper над `chezmoi apply` + post-verify через `dot doctor`. Показывает before/after drift count так что пользователь видит "было 5 WARN → стало 0 WARN" одной командой.
- **`dot snapshot`** — capture текущего состояния машины в canonical files + git commit prompt. Реюзает `scan-cli --capture`, `scan-macos-defaults.sh` (capture baseline), `scan-login-autostart.sh` (regen login-items.txt). После — `git diff` + интерактивный commit (без auto-push).
- **`dot pull`** — `chezmoi git -- pull origin <branch>` + `chezmoi apply` + `dot doctor`. Получить изменения с другой машины и применить за один шаг.

## Why this slice matters

Текущий цикл sync между Маками вручную:
1. `cd ~/Documents/Projects/dotforge && git pull`
2. `chezmoi apply`
3. `bootstrap.sh doctor`
4. Если drift — что-то ещё руками

После 2c один шаг: `dot pull`. И:
- `dot doctor` (diagnose) → `dot apply` (fix via chezmoi) → `dot doctor` (verify) — три команды для самого частого workflow
- `dot snapshot` (capture machine state) → review diff → commit — для эпизодического "captured changes into canonical state"

## Design decisions still open (brainstorm these in Phase 0)

1. **`dot apply` post-verify UX** — как показать before/after? Options:
   - Cache `dot doctor` output в /tmp до apply, после apply diff'нуть
   - Просто запустить doctor дважды и распечатать оба summary
   - Показать только delta (rough: `5 WARN → 0 WARN, 0 FAIL → 0 FAIL`)

2. **`dot snapshot` scope** — какие scanners запускать? Все три (cli + macos + autostart) или selective флаги (`--include=cli,macos`)?

3. **`dot snapshot` commit-prompt** — gum confirm для каждого изменённого файла или один общий confirm?

4. **`dot pull` interactivity** — что если `chezmoi git pull` падает (merge conflict, no network)? Bail с понятной ошибкой. Если pull OK но `apply` создаёт drift — продолжать до `doctor` или останавливать?

5. **Selective apply** — `dot apply --check=brewfile` хочется? Это уже выходит за scope `chezmoi apply` (chezmoi не имеет такого фильтра). Возможно реализовать через `chezmoi apply --include=scripts` + специальная env-var.

6. **`dot apply --dry-run`** — оборачивает `chezmoi diff` вместо `chezmoi apply`. Полезно?

## Suggested AC structure (refine in Phase 2)

### `dot apply`
1. `dot apply` runs `chezmoi apply`, exits 0 on success
2. Before-apply: cache `dot doctor` summary (WARN/FAIL counts)
3. After-apply: re-run `dot doctor`, print delta in green/yellow
4. Exit code reflects post-apply doctor exit code
5. `dot apply --dry-run` → `chezmoi diff` без mutate

### `dot snapshot`
1. Runs `scan-cli --capture` (default ON)
2. Runs scan-macos to update baseline (default ON; opt-out via `--no-macos`)
3. Runs scan-autostart to update login-items.txt (default ON; opt-out via `--no-autostart`)
4. After captures: `git status` показывает изменения
5. If user wants: gum confirm → `git add <files> && git commit -m "snapshot: ..."` (без push)

### `dot pull`
1. `chezmoi git -- fetch origin <branch>` (branch from $DOTFORGE_BRANCH)
2. If behind: `chezmoi git -- pull --ff-only`
3. `chezmoi apply`
4. `dot doctor`

## File-touch (preliminary — verify in Phase 1)

| Task | Files | Notes |
|------|-------|-------|
| 1 — Extend `executable_dot` dispatcher | `chezmoi/dot_local/bin/executable_dot` | Add 3 new case branches; possibly extract logic into `scripts/dot-apply.sh` etc. if functions get >20 lines each |
| 2 — `scripts/dot-apply.sh` (NEW) | NEW | If logic doesn't fit inline in shim |
| 3 — `scripts/dot-snapshot.sh` (NEW) | NEW | Wraps scan-cli/scan-macos/scan-autostart + git commit prompt |
| 4 — `scripts/dot-pull.sh` (NEW) | NEW | Wraps chezmoi git pull + apply |
| 5 — Docs | `README.md`, `docs/usage.md` | Subcommands updated, `## dot CLI` section extended |

## Predecessors / context to read

- [v_2026-05-16-dot-cli-archetypes-design.md](v_2026-05-16-dot-cli-archetypes-design.md) — slice 2a + 2b design
- [v_2026-05-16-dot-doctor-implementation.md](v_2026-05-16-dot-doctor-implementation.md) — slice 1 doctor design
- `chezmoi/dot_local/bin/executable_dot` — current shim to extend
- `scripts/doctor.sh` — to call for post-verify
- `scripts/scan-cli.sh`, `scripts/scan-macos-defaults.sh`, `scripts/scan-login-autostart.sh` — to wrap

## Special requirements (lessons from prior session)

1. **Forbid `git switch` / CWD-drift defense**: every Phase 3 prompt MUST include absolute paths + `git -C <worktree>` form + `git branch --show-current` paste at top of agent report. Two agents in 2026-05-16 committed to main instead of feature worktree due to CWD inheritance.
2. **Mandatory git diff paste for doc tasks** (Task 5 docs especially). Prior session had Haiku claim file edits that never landed.
3. **Phase 8.5 advisor call** — mandatory before Phase 9 summary.
4. **`promptChoiceOnce` chezmoi quirk** (relevant if touching chezmoi.toml.tmpl): even with default param, non-TTY `chezmoi init` fails with "could not open a new TTY". Real cron/CI safety comes from `chezmoi apply` (which doesn't re-render config), not from default. Document this trade-off.

## Suggested execution flow

Wave 1 (parallel, isolated worktrees OK):
- Task 1+2: `dot apply` (sonnet, medium — orchestrates doctor capture + chezmoi apply + delta display)

Wave 2 (after Wave 1):
- Task 3: `dot snapshot` (sonnet, medium — wraps 3 scanners + git commit flow)

Wave 3 (after Wave 2):
- Task 4: `dot pull` (haiku or sonnet — simpler wrapper)

Wave 4 (after all):
- Task 5: docs (sonnet, mandatory diff paste)

Sequential probably simpler than parallel given the shim shares case dispatcher — single worktree, 4-5 commits.
