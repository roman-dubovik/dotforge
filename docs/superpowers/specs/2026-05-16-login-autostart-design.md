# Design: login items + LaunchAgents autostart

Date: 2026-05-16
Scope: Plan 1.5 expansion — automate app autostart on a fresh Mac

## Goal

On a fresh Mac after `bootstrap.sh setup`, the user should see the same apps starting at login and the same custom background services running as on their current canonical Mac, without manually re-toggling each one in System Settings → General → Login Items or re-creating `~/Library/LaunchAgents/*.plist` files.

Two parallel mechanisms macOS offers:

1. **Login Items** (System Settings → General → Login Items) — apps that auto-open at user login. Managed via `osascript`/System Events scripting bridge for user-toggleable entries.
2. **LaunchAgents** (`~/Library/LaunchAgents/*.plist`) — launchd plists for background services / cron-like jobs / custom scripts that should run when the user logs in (or on a schedule). Managed via `launchctl bootstrap` / `bootout`.

## File-touch matrix

| Task | Files (exact paths) | Touches |
|------|---------------------|---------|
| 1 — Hook | `chezmoi/.chezmoiscripts/run_onchange_70-apply-login-autostart.sh` | new |
| 1 — Baseline data | `login-items.txt` (repo root) | new — list of `/Applications/<App>.app` paths |
| 1 — LaunchAgents tree | `chezmoi/private_dot_Library/private_LaunchAgents/` | new dir, user-curated `.plist.tmpl` files inside |
| 2 — Scan helper | `scripts/scan-login-autostart.sh` | new |
| 2 — Bootstrap subcommand | `bootstrap.sh` | add `scan-autostart` subcommand wired same as `scan-macos` |
| 3 — Docs | `README.md`, `docs/usage.md` | add subcommand entry + hook reference subsection |

No overlap between tasks 1 and 2. Task 3 is sequential after both.

## Patterns to follow

- Hook structure: mirror `run_onchange_60-apply-macos-defaults.sh` (set -uo pipefail, lib/log.sh, DRY_RUN support, no `-e`, individual failures log_warn and continue, final log_ok summary)
- Scan helper structure: mirror `scripts/scan-macos-defaults.sh` (baseline-driven, --diff mode, exit 0 on missing keys)
- Bootstrap subcommand wiring: mirror `cmd_scan_macos` (4 places: top comment, menu, validator, dispatcher)
- chezmoi private_dot prefix: required because LaunchAgents live in `~/Library/` which chezmoi marks as private by default

## External constraints

- **Login Items via osascript** — uses `tell application "System Events"`. macOS 13+ may prompt for Automation permission on first invocation. Hook must handle that gracefully: if osascript exits with permission error, log_warn and continue (user can grant later and re-run).
- **App path matters, not Bundle ID** — System Events identifies login items by absolute path (`/Applications/Foo.app`). Apps installed via cask end up there reliably. MAS apps too.
- **LaunchAgents that brew/casks already create** — Docker Desktop, Backblaze, Karabiner-Elements, Brewfile-installed casks create their own `~/Library/LaunchAgents/*.plist` at install time. These MUST NOT be in dotforge — they self-restore on `brew bundle`. Dotforge tracks only **custom user** LaunchAgents (your own cron-like jobs, custom scripts).
- **Filter for "custom" detection** — scan helper distinguishes app-installed (Label starts with `com.docker`, `com.backblaze`, `com.googlecode.iterm2`, `com.apple.*`, etc.) from user-managed (typically labels like `local.<name>`, `com.<yourgithub>.<name>`, or anything without a well-known prefix). Heuristic, not perfect — user reviews the scan output before adding to the repo.
- **No sudo required** — `~/Library/LaunchAgents/` is user-writable, `launchctl bootstrap gui/$UID` is per-user. We do NOT touch `/Library/LaunchDaemons/` (sudo-only, system-wide).
- **launchctl idempotency** — `launchctl bootstrap` errors if already loaded. Hook does `bootout` first (ignoring "Could not find service" errors), then `bootstrap`. Standard pattern.

## Acceptance Criteria

### Task 1 — Hook

1. `chezmoi/.chezmoiscripts/run_onchange_70-apply-login-autostart.sh` exists, executable, sources `lib/log.sh`.
2. **Login Items section:**
   - Reads `login-items.txt` (one app path per line, comments allowed: `# comment`, `/Applications/Rectangle.app`).
   - For each path that exists on disk: invoke `osascript` to ensure it's a login item. If already present, skip. If app not installed, log_warn and continue (don't fail).
   - osascript Automation-permission error: log_warn with hint "grant Automation access in System Settings → Privacy & Security → Automation, then re-run", continue.
3. **LaunchAgents section:**
   - For each `*.plist` in `~/Library/LaunchAgents/` that was put there by chezmoi (any file under that path), run `launchctl bootout gui/$UID/<label> 2>/dev/null || true` (ignore "not loaded") then `launchctl bootstrap gui/$UID <path>`.
   - If `bootstrap` fails (malformed plist, etc.), log_warn with the plist path and continue.
   - Note: chezmoi takes care of WRITING the plists into `~/Library/LaunchAgents/` because they live under `chezmoi/private_dot_Library/private_LaunchAgents/`. The hook ONLY handles the launchctl side.
4. Hook supports `DRY_RUN=1` — prints "would: osascript ..." / "would: launchctl bootstrap ..." instead of executing.
5. Hook exits 0 even on individual failures.
6. Final log_ok summary: `applied N login items, loaded M launch agents (X warnings)` — count failures explicitly so the summary doesn't lie.

### Task 2 — Scan helper + bootstrap.sh subcommand

1. `scripts/scan-login-autostart.sh` exists, executable.
2. **Login Items scan:**
   - Outputs current login items as ready-to-paste lines for `login-items.txt`: one `/Applications/Foo.app` per line (read via osascript `get path of every login item`).
   - Header comment lists how to use the output.
3. **LaunchAgents scan:**
   - Lists every `.plist` in `~/Library/LaunchAgents/` with its Label, target binary, and a "likely source" guess (cask name if path matches a known cask, else "custom/unknown").
   - Output format: human-readable table, NOT direct `defaults write`-style replay commands — because user has to manually decide which to version.
   - Footer hint: "To track a plist, copy it under chezmoi/private_dot_Library/private_LaunchAgents/ in the repo."
4. Optional `--diff` flag: compare current login-items with `login-items.txt` baseline, show only paths missing from one side or the other.
5. `bootstrap.sh` gains `scan-autostart` subcommand wired in 4 places (top comment, show_main_menu, validation case, dispatcher case + new cmd_scan_autostart function).

### Task 3 — Docs

1. `README.md`: Subcommands section gets `scan-autostart` entry. "What it does" step list gets a new step about login items + launch agents.
2. `docs/usage.md` "Chezmoi hooks (Plan 1.5 additions)" section gets a new subsection for the autostart hook.

## Open questions

None — all clarified in Phase 0.

## Test plan

- DRY_RUN smoke on hook (must list intended osascript + launchctl calls, exit 0)
- shellcheck on all new .sh
- /bin/bash -n (macOS bash 3.2) syntax check
- `bootstrap.sh scan-autostart` on this Mac: must output current login items (likely empty for fresh user) + list of any LaunchAgents
- After running hook on this Mac (manual smoke): System Settings → General → Login Items should show entries from `login-items.txt` ticked. `launchctl list | grep <our-label>` should show loaded agents.

## What we explicitly DO NOT do

- No `/Library/LaunchDaemons/` (would need sudo)
- No SMAppService bridging (macOS 13+ developer-only API, no first-class CLI)
- No automatic capture of app-installed LaunchAgents into the repo (those belong to the apps themselves and rebuild on `brew bundle`)
- No GUI dialogs / gum prompts inside the hook — chezmoi apply runs non-interactively
