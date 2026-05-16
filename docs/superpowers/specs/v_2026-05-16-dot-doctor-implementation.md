# Implementation Plan: `dot doctor` (Plan 2 starter)

Date: 2026-05-16
Status: READY TO EXECUTE
Predecessors: Plan 1 (closed), Plan 1.5 (closed — curl-toolchains, macOS defaults, login autostart)

## Context

First slice of Plan 2: a unified diagnostic command that answers "is this Mac in sync with the canonical state?" with one command, without modifying anything.

Replaces the current manual ritual of running `chezmoi diff`, `brew bundle check`, `ls ~/.ssh`, `scan-macos --diff`, `scan-autostart --diff`, and eyeballing toolchain versions separately.

**Design reference:** plan flow is part of larger Plan 2 (archetypes + dot CLI + feature flags); this implementation does only `dot doctor`. Persistent archetypes, `dot apply/snapshot/pull`, feature flags — deferred.

**Naming decision:** for this first slice, the command lives as `bootstrap.sh doctor` (mirrors existing `scan-cli`, `scan-macos`, `scan-autostart` pattern). Future `dot` CLI wrapper (when Plan 2 lands fully) will call the same `scripts/doctor.sh` underneath.

## Scope: what `doctor` checks

For each section: a check function reports `OK` / `WARN` / `FAIL` with one-line evidence. No state mutations anywhere.

1. **chezmoi state** — `chezmoi diff` non-empty → WARN ("X files would change on apply"). `chezmoi.toml` missing → FAIL ("chezmoi not initialized, run setup first").
2. **Brewfile divergence** — `brew bundle check --no-upgrade --file=<active-brewfile>` exit 1 → WARN ("missing N packages"); exit 0 → OK. (Active brewfile = `Brewfile.local` if exists, else canonical `Brewfile`.)
3. **CLI globals replayed** — parse `cli-globals.txt`, check each `<source>:<package>` is installed (`npm ls -g <pkg> --depth=0 2>/dev/null`, similar for pnpm/cargo/go/pip). Count missing.
4. **Curl-based toolchains** — presence check for each of: `~/.oh-my-zsh/oh-my-zsh.sh`, `$ZSH_CUSTOM/themes/powerlevel10k/`, 3 zsh plugins, `~/.nvm/nvm.sh`, `~/Library/pnpm/pnpm` OR `~/.local/share/pnpm/pnpm`, `~/.maestro/bin/maestro`.
5. **SSH keys present** — for each entry in `dotforge-ssh-<profile>` and `dotforge-ssh-<profile>-<machine>` Bitwarden items: check the corresponding files exist in `~/.ssh/`. **Skip bw API check if vault is locked** — that requires master password, not OK in non-interactive doctor. Just file existence.
6. **macOS defaults divergence** — call `scripts/scan-macos-defaults.sh --diff` and count divergent lines (those starting with `defaults write`).
7. **Login items + LaunchAgents divergence** — call `scripts/scan-login-autostart.sh --diff` and count divergent entries.
8. **Git: dotforge repo current** — `chezmoi git -- fetch origin` then check if local main is behind origin/main.

## Output

```
dotforge doctor — 2026-05-16T18:23

[OK]   chezmoi state         no pending changes
[WARN] Brewfile              2 missing: htop, lazydocker
[OK]   CLI globals           9/9 npm packages present
[OK]   Curl-toolchains       8/8 installed
[OK]   SSH keys              2 keys present (personal scope)
[WARN] macOS defaults        3 keys diverge from baseline (run scan-macos --diff)
[OK]   Login items           5 items match baseline
[OK]   LaunchAgents          0 chezmoi-managed (no drift)
[OK]   Repo                  up to date with origin/main

Summary: 7 OK, 2 WARN, 0 FAIL
```

Plain text by default (so `dot doctor | grep WARN` works), with `--color` opt-in.

Exit codes:
- 0: all OK
- 1: ≥1 WARN, 0 FAIL
- 2: ≥1 FAIL (e.g. chezmoi not initialized — fundamentally broken setup)

## Task breakdown

### Task 1 — `scripts/doctor.sh` orchestrator + all check functions

- **Complexity:** Medium
- **Model:** sonnet
- **Worktree:** main tree (continue accumulating commits on `claude/quirky-solomon-7ed747` if it still exists, else fresh feature branch off main)
- **Files to create:** `scripts/doctor.sh` (executable)
- **Pattern to follow:** [scripts/scan-macos-defaults.sh](scripts/scan-macos-defaults.sh) for REPO_ROOT detection + section structure; [chezmoi/.chezmoiscripts/run_onchange_30-install-cli-globals.sh](chezmoi/.chezmoiscripts/run_onchange_30-install-cli-globals.sh) for parsing `cli-globals.txt`.

**Implementation:**

- `set -uo pipefail`, no `-e`
- Source `lib/log.sh` (for `log_*` helpers if any are used; doctor mostly uses its own status printer)
- 8 check functions: `check_chezmoi`, `check_brewfile`, `check_cli_globals`, `check_curl_toolchains`, `check_ssh_keys`, `check_macos_defaults`, `check_login_autostart`, `check_repo_sync`
- Each function: prints exactly one status line in the format `[STATUS] <label-padded-22-chars> <details>`. Sets a global counter `OK_COUNT`/`WARN_COUNT`/`FAIL_COUNT`.
- Main: call each check in order, print blank line + summary line, exit with code 0/1/2.
- `--no-color` flag (default colorless to be pipe-friendly; `--color` enables ANSI; auto-detect TTY isatty as bonus).
- `--check=<name>` flag to run a single check (debugging convenience).
- Always idempotent + read-only. No fallback to actions like "fix this for me".

**Edge cases:**

- chezmoi.toml missing → check_chezmoi returns FAIL with "chezmoi not initialized, run `bootstrap.sh setup`"
- Brewfile.local missing (no customizer ever ran) → use canonical `Brewfile` for check
- cli-globals.txt missing → check_cli_globals returns WARN with "cli-globals.txt missing, run `bootstrap.sh scan-cli --capture` first"
- npm/pnpm/cargo/go not on PATH → for each line in cli-globals.txt that references a missing manager, report the manager as the gap (not the package)
- BW vault locked → check_ssh_keys reports OK if all expected files exist on disk; does NOT attempt `bw get` (interactive)
- `scan-macos-defaults.sh --diff` / `scan-login-autostart.sh --diff` output parsing: count lines starting with `defaults write` (macos) or `+`/`-` (login)
- `chezmoi git` fails (no network) → check_repo_sync returns WARN with "could not fetch origin"

**Acceptance criteria:**

1. `scripts/doctor.sh` exists, executable, shellcheck clean, bash 3.2 syntax-pass
2. Running on current Mac prints 8 status lines + summary + non-zero exit if drift exists (likely WARN for macos-defaults, OK for everything else)
3. `--check=chezmoi` runs only chezmoi check, exit code reflects ONLY that check
4. `--color` and TTY auto-detect work — ANSI escapes only when appropriate
5. Re-running on no-drift machine: exits 0 with 8 OKs
6. Force-degrade scenarios (manually remove `~/.oh-my-zsh` then run doctor): correctly reports Curl-toolchains WARN
7. Hidden test: shellcheck + DRY_RUN-not-applicable (doctor is read-only by design, no DRY_RUN needed)

### Task 2 — `bootstrap.sh doctor` subcommand wiring

- **Complexity:** Simple
- **Model:** haiku (mechanical wiring, well-known pattern)
- **Worktree:** same as Task 1
- **Files to edit:** `bootstrap.sh` (4 places, same as `scan-macos` / `scan-autostart`)
- **Pattern:** mirror `cmd_scan_macos` exactly

**Implementation:**

1. Top-of-file comment block: add `#   bootstrap.sh doctor       # run diagnostic checks (read-only)`
2. `show_main_menu`: add `"doctor    — Run diagnostic checks against canonical state (read-only)"` to the gum choose list
3. Validation case in `main()`: add `doctor` to the list
4. Dispatcher case: `doctor)   install_bootstrap_deps gum; cmd_doctor "$@" ;;`
5. New `cmd_doctor` function: thin wrapper, exactly like `cmd_scan_macos` / `cmd_scan_autostart`:
   ```bash
   cmd_doctor() {
       local repo_root
       repo_root="$(get_repo_root)"
       if [[ -z "$repo_root" || ! -x "$repo_root/scripts/doctor.sh" ]]; then
           err "Repo not cloned yet (run 'setup' first)."
       fi
       bash "$repo_root/scripts/doctor.sh" "$@"
   }
   ```

**Acceptance criteria:**

1. `bootstrap.sh doctor` from CLI runs `scripts/doctor.sh`
2. `bootstrap.sh` with no args shows new menu entry
3. `bootstrap.sh --help` lists `doctor` in the subcommand block
4. shellcheck on `bootstrap.sh` clean

### Task 3 — Docs

- **Complexity:** Simple
- **Model:** sonnet (Haiku was unreliable for docs last session — mandatory `git diff` paste in report)
- **Worktree:** same
- **Files to edit:** `README.md`, `docs/usage.md`

**Implementation:**

- `README.md` Subcommands section: add `doctor` entry after `scan-autostart`
- `README.md` Roadmap section: change "Plan 2 — Archetypes and `dot` CLI (pending)" to indicate `doctor` is the first slice that landed (e.g. "Plan 2 (in progress) — `dot doctor` shipped, persistent archetypes + `dot apply/snapshot/pull` + feature flags pending")
- `docs/usage.md`: add a new section after "Chezmoi hooks (Plan 1.5 additions)" titled "Diagnostic — `bootstrap.sh doctor`" with example output and exit code semantics.

**Acceptance criteria:**

1. README has `doctor` in Subcommands list
2. README Roadmap reflects Plan 2 partial progress
3. usage.md has new doctor section with example output and `--check=<name>` mention
4. **Mandatory:** agent must paste `git diff --stat README.md docs/usage.md` AND `git diff README.md` first 30 lines in their report (lesson from prior doc-task false-success)

## Execution order

1. Wave 1 parallel: Task 1 (doctor.sh, Sonnet) + Task 2 (bootstrap.sh wiring, Haiku)
2. Wave 2 sequential: Task 3 (docs, Sonnet)

## Dependencies between tasks

- Task 2 references Task 1's output (`scripts/doctor.sh`), but only via thin shell call — they don't share function definitions. Parallel OK.
- Task 3 documents Task 1 + 2 — must run after.

## Risks / open questions

1. **`brew bundle check --no-upgrade`** existence — verify the flag is current (Homebrew 4.x). If syntax changed, fall back to comparing `brew list --formula` + `brew list --cask` against parsed Brewfile.
2. **`chezmoi git fetch origin`** behavior — works only after chezmoi init. If user is running doctor on a non-bootstrapped Mac, `check_repo_sync` should degrade gracefully (already handled in design: WARN, not FAIL).
3. **cli-globals.txt parsing edge cases** — what if a line says `npm:@scope/package` (scoped npm)? `npm ls -g @scope/package` must work; verify against actual entries in `cli-globals.txt`.
4. **TTY color auto-detect** — `[[ -t 1 ]]` is the standard idiom; verify it works under chezmoi-apply context too (where stdout may be a pipe).

## Worktree setup checklist

- [ ] If `claude/quirky-solomon-7ed747` worktree from prior session still exists: continue using it. `pnpm install` etc. not applicable (no node project).
- [ ] If starting fresh: `git checkout -b feature/dot-doctor` off main. Worktree under `.claude/worktrees/` per project convention.
- [ ] No `.env.local` copying needed (project is pure shell scripts + chezmoi templates).
- [ ] Verify shellcheck installed (`brew list shellcheck`) — already in Brewfile.
- [ ] Verify `chezmoi` initialized OR running on a machine where dotforge has been set up.
- [ ] Plan files (this one + design refs) already in repo — no extra copy needed.

## What we explicitly DO NOT do in this slice

- No `dot` binary at `~/.local/bin/dot` yet — that's part of the larger Plan 2 CLI wrapper task
- No `dot apply` / `dot snapshot` / `dot pull` — separate future tasks
- No persistent archetypes (still part of Plan 2 future)
- No feature flags (Plan 2 future)
- No auto-fix mode (`dot doctor --fix`) — doctor stays read-only forever; fixing is `dot apply`'s job
- No interactive prompts — doctor must be non-interactive (pipeable, cron-friendly)

## Test plan

After implementation:

1. `bash scripts/doctor.sh` on current Mac → 8 status lines + summary, exit code reflects highest severity
2. `bash scripts/doctor.sh --check=chezmoi` → single-line output
3. `bash scripts/doctor.sh --color` → ANSI colors
4. `bash scripts/doctor.sh | cat` → no ANSI (pipe detected)
5. Force a drift: `defaults write com.apple.dock tilesize -int 999` then `bash scripts/doctor.sh` → macOS defaults WARN
6. `bootstrap.sh doctor` → same as direct invocation
7. `bootstrap.sh doctor --check=brewfile` → arg pass-through works

## Quality gates per task

Per task (before commit):
- `shellcheck <file>` — zero errors
- `/bin/bash -n <file>` — pass
- Re-run `bash scripts/doctor.sh` after edits — must still complete cleanly

Cross-cutting (before declaring done):
- Re-run independent verifier (Sonnet, separate agent) on AC for all 3 tasks
- pr-review-toolkit code-reviewer + silent-failure-hunter on each commit
- Phase 8.5 advisor call before Phase 9 summary
- README diff must include `doctor` row in Subcommands
- usage.md diff must include new Diagnostic section
