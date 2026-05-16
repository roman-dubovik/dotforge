# Design: `dot` CLI + Persistent Archetypes (Plan 2 — slices 2a + 2b)

Date: 2026-05-16
Status: READY TO EXECUTE
Predecessor: Plan 2 slice 1 (`bootstrap.sh doctor`, shipped same day)

## Goal

Two foundational pieces of Plan 2:

1. **`dot` CLI shim** at `~/.local/bin/dot` — unified namespace for diagnostics and future operations. This session lands `dot doctor`, `dot help`, `dot version`. `dot apply`, `dot snapshot`, `dot pull` deferred to slice 2c.
2. **Persistent Brewfile archetype** — store `brewfile_archetype` in chezmoi data; on every `chezmoi apply`, the brewfile hook auto-regenerates `Brewfile.local` from the chosen archetype if the file is missing. Manual customization (existing `Brewfile.local`) is always respected.

## Out of scope (deferred to 2c / 2d)

- `dot apply` (chezmoi apply + post-verify) — slice 2c
- `dot snapshot` (capture canonical state + commit prompt) — slice 2c
- `dot pull` (chezmoi git pull + apply) — slice 2c
- Feature flags (`data.features.docker`, etc.) — slice 2d
- Re-pick-archetype CLI flow — minor follow-up; for now, archetype change = manually edit `~/.config/chezmoi/chezmoi.toml`, delete `Brewfile.local`, run `chezmoi apply`

## File-touch matrix

| Task | Files (exact paths) | Touches |
|------|---------------------|---------|
| 1 — `dot` shim | `chezmoi/dot_local/bin/executable_dot` (NEW) | new shim, ~30 lines |
| 2 — Archetype data var | `chezmoi/.chezmoi.toml.tmpl`, `bootstrap.sh` (chezmoi init args around line 166) | +1 `promptChoiceOnce` field, +1 init arg |
| 3 — Hook + customize CLI flag | `chezmoi/.chezmoiscripts/run_onchange_20-apply-brewfile.sh.tmpl`, `scripts/customize-brewfile.sh` (add `--archetype <name>` non-interactive mode) | template var read + auto-regenerate; new CLI flag |
| 4 — Docs | `README.md`, `docs/usage.md` | new section `dot CLI`, archetype lifecycle doc |

**Conflict analysis:** Task 1 touches only the shim file. Task 2 touches `.chezmoi.toml.tmpl` and `bootstrap.sh`. Task 3 touches the hook and `customize-brewfile.sh`. Task 4 has monopoly on docs. **No file overlap between any tasks.**

**Dependency graph:**
- Task 3 reads `data.brewfile_archetype` from chezmoi → depends on Task 2 (data var must exist first)
- Task 1 independent of 2/3
- Task 4 documents 1+2+3 → must run last

**Execution order:**
- Wave 1 (parallel-ish, but we run sequentially in shared worktree): Task 1, then Task 2
- Wave 2: Task 3 (after Task 2)
- Wave 3: Task 4 (after 1+2+3)

## Patterns to follow

- **`dot` shim repo discovery** — pattern B from existing hooks: `SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"; REPO_ROOT="${SOURCE_PATH%/chezmoi}"`
- **Shim dispatcher** — mirror `bootstrap.sh cmd_doctor` (lines 289–296): `DOTFORGE_BRANCH="${DOTFORGE_BRANCH:-main}" bash "$REPO_ROOT/scripts/doctor.sh" "$@"`
- **chezmoi.toml.tmpl prompts** — same `promptChoiceOnce` pattern as existing `profile` field in `chezmoi/.chezmoi.toml.tmpl`
- **bootstrap.sh init args** — mirror existing `--promptString "machine_name=..."` and `--promptChoice "profile=..."` (around line 166–169)
- **customize-brewfile.sh --archetype** — there are already 4 internal archetype options (`full`, `minimal-dev`, `cli-server`, `custom`). The script is interactive today (via `gum choose`). Add a `--archetype <name>` flag that bypasses the prompt and picks sections programmatically (reuse internal `select_sections_for_archetype` logic if it exists, or refactor minimally).
- **Hook auto-regenerate** — in `run_onchange_20-apply-brewfile.sh.tmpl`, when `Brewfile.local` missing AND `{{ .brewfile_archetype }}` ≠ "custom" → call `bash "$REPO_ROOT/scripts/customize-brewfile.sh" --archetype "$ARCH" --no-install`. Then fall through to existing apply logic.

## External constraints

- bash 3.2 compatible (macOS default)
- `set -uo pipefail` for orchestrator scripts (NOT `-e`), `set -euo pipefail` only for simple linear scripts
- shellcheck clean is a release-blocker
- Conventional Commits, scope = `bootstrap` / `chezmoi` / `dot` / `docs`. No Co-Authored-By
- Existing user expectation: README.md may have uncommitted user-pending changes → tasks must NOT `git add -A`; selective `git add <file>` only
- No `git switch`/`git checkout <other>` mid-task

## Archetype lifecycle (design decision)

State machine:

```
fresh setup
  │
  ├─ user runs `bootstrap.sh setup`
  ├─ chezmoi prompts: machine_name? profile? archetype?
  ├─ chezmoi.toml saves: brewfile_archetype = "minimal-dev" (e.g.)
  │
  ├─ bootstrap.sh asks "customize Brewfile?" (existing flow, unchanged)
  │    └─ if YES → `customize-brewfile.sh --no-install` → Brewfile.local written
  │
  ├─ chezmoi apply
  │    └─ hook run_onchange_20-apply-brewfile.sh.tmpl
  │         ├─ if Brewfile.local exists → use it (whatever user/customize wrote)
  │         ├─ else if archetype == "custom" → use canonical Brewfile (no auto-pick)
  │         └─ else → call customize-brewfile.sh --archetype $ARCH --no-install → Brewfile.local appears → use it

later: re-apply on same machine
  ├─ chezmoi apply (no re-prompt — archetype is `promptChoiceOnce`)
  ├─ hook same logic: respects existing Brewfile.local

later: switch machine (fresh setup, same profile)
  ├─ chezmoi prompts archetype again (fresh chezmoi.toml on new machine)
  ├─ user picks (could be different from another machine — that's fine, archetype is per-machine)

later: user wants to change archetype
  ├─ edit ~/.config/chezmoi/chezmoi.toml — change brewfile_archetype = "full"
  ├─ delete Brewfile.local
  ├─ chezmoi apply → hook regenerates Brewfile.local from new archetype
```

## Acceptance Criteria

### Task 1 — `dot` shim

1. `chezmoi/dot_local/bin/executable_dot` exists, shellcheck clean, bash -n passes.
2. After `chezmoi apply` (or manual symlink for testing), `~/.local/bin/dot` exists, is executable.
3. `dot doctor` runs the same as `bootstrap.sh doctor` — single-line output for `dot doctor --check=chezmoi`, full 8-line output for `dot doctor`.
4. `dot help` (or `dot` with no args) prints usage with available subcommands (`doctor`, `help`, `version`) and a one-line note that `apply`/`snapshot`/`pull` are coming.
5. `dot version` prints repo HEAD short hash + branch name (`git -C $REPO_ROOT rev-parse --short HEAD` + `git -C $REPO_ROOT branch --show-current`).
6. Unknown subcommand → exit 1 with usage hint.
7. `DOTFORGE_BRANCH` env var forwarded to `doctor.sh`.
8. Tests: shellcheck + bash -n + smoke (`bash chezmoi/dot_local/bin/executable_dot doctor --check=chezmoi` → single line, exit 0/1).

### Task 2 — Archetype data var

1. `chezmoi/.chezmoi.toml.tmpl` has new `brewfile_archetype` field via `promptChoiceOnce` with choices `["full", "minimal-dev", "cli-server", "custom"]` and default `"full"`.
2. `bootstrap.sh setup` flow asks for archetype via `gum choose` BEFORE chezmoi init (mirroring existing machine_name/profile pattern); passes it to chezmoi init as `--promptChoice "brewfile_archetype=..."`.
3. On a clean `bootstrap.sh setup` run, `~/.config/chezmoi/chezmoi.toml` has `brewfile_archetype = "<chosen>"` after init.
4. Existing `machine_name` and `profile` prompts unchanged.
5. Tests: shellcheck on bootstrap.sh, `bash -n` on bootstrap.sh, smoke against `chezmoi data | jq .brewfile_archetype` on a test machine if available (otherwise visual diff of `.chezmoi.toml.tmpl`).

### Task 3 — Hook auto-regenerate

1. `scripts/customize-brewfile.sh` accepts new flag `--archetype <name>` (full/minimal-dev/cli-server) that bypasses interactive prompt and writes Brewfile.local non-interactively.
2. `--archetype custom` is rejected with a usage error (custom requires interactive).
3. `run_onchange_20-apply-brewfile.sh.tmpl` reads `{{ .brewfile_archetype }}` template variable.
4. Hook logic: if `Brewfile.local` exists → use it (current behavior preserved). Else if archetype == "custom" → use canonical `Brewfile`. Else → call `customize-brewfile.sh --archetype "$ARCH" --no-install`, then use generated `Brewfile.local`.
5. Hook prints status: which file is being used and why (1 line, log_info).
6. shellcheck clean on customize-brewfile.sh (the template hook is not shellchecked because of `{{ }}` substitutions — bash -n alone after substitution, but we'll run shellcheck with `-x` or just manual check).
7. Tests: bash -n on customize-brewfile.sh, manual smoke `bash scripts/customize-brewfile.sh --archetype minimal-dev --no-install --output /tmp/test.brewfile` → file written, contains expected sections.

### Task 4 — Docs

1. README.md "Subcommands" section: add a brief `dot` line ("preferred entry point for diagnostics; `dot doctor` = `bootstrap.sh doctor`").
2. README.md "Roadmap" Plan 2 line: update to reflect 2a+2b shipped, 2c+2d pending.
3. `docs/usage.md`: new section "## `dot` CLI" with available subcommands and example output.
4. `docs/usage.md`: new section "## Brewfile archetypes" (or extend existing "Customizing the Brewfile") with the lifecycle state machine above (simplified) and "how to change archetype after setup" instructions.
5. **Mandatory:** agent pastes `git diff --stat README.md docs/usage.md` and first 30 lines of each `git diff` in the report (lesson from prior session).

## Risks / open questions

1. **chezmoi prompts during init with existing chezmoi.toml** — if a user already has `chezmoi.toml` from a prior install (without `brewfile_archetype`), will chezmoi prompt for the new variable on next `chezmoi apply`? **Yes**, `promptChoiceOnce` re-prompts if the key is missing. So existing users on `main` will get prompted once. Acceptable.
2. **customize-brewfile.sh refactor scope** — adding `--archetype <name>` flag may require non-trivial refactor depending on how the script is structured. The research said "16 selectable sections + 4 archetypes, sections parsed by `# ── Title ──` markers". If archetype logic is already in `select_sections_for_archetype` function or equivalent, the flag is a 10-line addition. If interleaved with gum prompts, may be 30+ lines.
3. **bash 3.2 + chezmoi template `{{ if }}`** — template can output bash that branches on archetype; need to confirm chezmoi templating handles single-line conditionals OR the bash itself reads an exported var. Cleanest: hook reads `ARCHETYPE="{{ .brewfile_archetype }}"` as bash var at top, then pure bash logic.
4. **Default archetype = "full"** — safe default since current behavior (no Brewfile.local) installs everything. Pre-existing users get `full` on first re-prompt unless they pick something else.

## Worktree strategy

Single shared worktree `.claude/worktrees/feature-dot-cli-archetypes` (off main `3a6ca45`). Sequential execution — no parallel agents — to avoid orphan-worktree buildup from prior sessions.

## Quality gates per task

- shellcheck on every modified `.sh`
- `/bin/bash -n` on every modified script
- For chezmoi template: `chezmoi execute-template < file` smoke if chezmoi is on PATH
- Final cross-cutting smoke: `bash bootstrap.sh doctor --check=chezmoi`, `bash chezmoi/dot_local/bin/executable_dot doctor --check=chezmoi`, `bash scripts/customize-brewfile.sh --archetype minimal-dev --no-install --output /tmp/smoke.brewfile && wc -l /tmp/smoke.brewfile`

## Plan 2 progress tracker

- ✅ 2 slice 1: `bootstrap.sh doctor` (shipped 2026-05-16, commits 02f748d..697b90e)
- 🟡 **this session: 2a (dot CLI namespace, doctor only) + 2b (archetype persistence)**
- ⏭ 2c: `dot apply` / `dot snapshot` / `dot pull`
- ⏭ 2d: feature flags
