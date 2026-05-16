# Design: bootstrap completeness — curl toolchains + macOS defaults

Date: 2026-05-16
Scope: Plan 1.5 (closes gap before Plan 2 starts)

## Goal

Reduce manual post-bootstrap steps on a fresh Mac by automating two categories that are currently silent gaps:

1. **Curl-based toolchains** (oh-my-zsh, powerlevel10k, nvm, pnpm, maestro) — currently listed only as comments in `Brewfile`. The managed `.zshrc` already depends on them, so a fresh-Mac chezmoi-apply produces a shell that throws errors on every startup.
2. **macOS system defaults** (Dock / Finder / Keyboard / Screenshots / Trackpad) — currently zero automation. Every fresh Mac requires ~20 minutes of manual System Settings clicking.

Raycast is in scope only as installation (already in Brewfile). Sync mechanism is deferred.

## File-touch matrix

| Task | Files (exact paths) | Touches |
|------|---------------------|---------|
| 1 — Curl toolchains hook | `chezmoi/.chezmoiscripts/run_onchange_25-install-curl-toolchains.sh` | new file |
| 1 — Brewfile manual-install block | `Brewfile` (lines ~120-124, "Non-brew toolchains" comment) | edit comment to point to new hook |
| 1 — Bootstrap subcommand (optional) | `bootstrap.sh` | none (hook auto-runs via chezmoi apply) |
| 2 — macOS defaults hook | `chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh` | new file |
| 2 — Scan helper | `scripts/scan-macos-defaults.sh` | new file |
| 2 — Bootstrap subcommand for scan | `bootstrap.sh` | add `cmd_scan_macos` + menu entry + dispatcher case |
| 2 — README subcommand list | `README.md` | add `scan-macos` entry |
| 3 — usage.md mentions | `docs/usage.md` | brief sections for both new hooks |

**No shared files between tasks 1 and 2** → can run fully parallel.

## Patterns to follow

- Hook numbering scheme (`run_onchange_NN-name.sh`): existing convention shown in `chezmoi/.chezmoiscripts/`. Brewfile is `20`, cli-globals is `30`, ssh-keys is `50`. **Curl-toolchains MUST be `25`** — between brew (provides git + curl) and cli-globals (needs npm/pnpm). **macOS defaults can be `60`** (independent, ordering not critical).
- Logging: source `lib/log.sh` (`log_ok` / `log_info` / `log_warn` / `log_error`) — already used by all existing hooks.
- Idempotency: every install must check "already there" before running. Existing pattern in `run_onchange_30-install-cli-globals.sh`.
- Hook template: see `run_onchange_50-pull-ssh-keys.sh.tmpl` for full pattern (set -euo pipefail, source lib/, SOURCE_PATH detection).
- bash strict mode: `set -euo pipefail` but unset `-e` selectively for installers that may exit non-zero on "already installed".

## External constraints

- `.zshrc` ([chezmoi/private_dot_zshrc.tmpl](chezmoi/private_dot_zshrc.tmpl)) sources `$ZSH/oh-my-zsh.sh` unconditionally → oh-my-zsh MUST be on disk before chezmoi expands .zshrc. chezmoi applies hooks in numeric order, and dotfile templates apply alongside. **Solution:** curl-toolchains hook (`25`) runs before chezmoi writes dotfiles in the same `apply` invocation when ordering allows; if first apply on a fresh Mac fails on .zshrc errors at the END of apply (non-fatal — they're shell-startup errors, not chezmoi errors), the SECOND apply will be clean.
- oh-my-zsh installer (`install.sh`) by default **clobbers `~/.zshrc`** with its own template. Must invoke with `--unattended --keep-zshrc` flags.
- `.zshrc` references plugins `zsh-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions` — these are oh-my-zsh **custom plugins**, must be `git clone`d into `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/`.
- macOS defaults: `killall Dock`, `killall Finder`, `killall SystemUIServer` to apply visual changes. Acceptable side effect (one-time visible flicker on fresh setup).
- Some `defaults write` keys require `sudo` (e.g. `/Library/Preferences/com.apple.loginwindow`). We intentionally stay in **user-level only** (`$HOME/Library/Preferences/`) — no sudo prompts during chezmoi apply.

## Acceptance Criteria

### Task 1 — Curl toolchains

1. `chezmoi/.chezmoiscripts/run_onchange_25-install-curl-toolchains.sh` exists and is executable.
2. Hook installs (in this order, all idempotent):
   - **oh-my-zsh** to `~/.oh-my-zsh` via official installer with `--unattended --keep-zshrc`. Skip if `~/.oh-my-zsh/oh-my-zsh.sh` exists.
   - **powerlevel10k** via `git clone --depth=1` into `$ZSH_CUSTOM/themes/powerlevel10k`. Skip if dir exists.
   - **zsh-syntax-highlighting**, **zsh-autosuggestions**, **zsh-completions** via `git clone --depth=1` into `$ZSH_CUSTOM/plugins/<name>`. Skip if dir exists.
   - **nvm** via `curl ... | bash`. Skip if `~/.nvm/nvm.sh` exists. After install, source nvm and run `nvm install --lts` to get a default Node (otherwise cli-globals hook silently skips).
   - **pnpm** via `curl ... | sh -`. Skip if `~/.local/share/pnpm/pnpm` or `~/Library/pnpm/pnpm` exists.
   - **maestro** via `curl -Ls "https://get.maestro.mobile.dev" | bash`. Skip if `~/.maestro/bin/maestro` exists.
3. Hook prints per-item status via `lib/log.sh` (`log_ok` already-installed, `log_info` installing, `log_error` failure).
4. Hook exits 0 even if individual installers fail (warn but continue) — failure of one toolchain must not block the rest of `chezmoi apply`.
5. Re-running `chezmoi apply` on a machine where all toolchains are installed prints all `✓ already installed` and adds zero new state.
6. Brewfile manual-install comment block (lines ~120-124) is updated to remove the curl one-liners (now automated) and only retain `tap`-style notes if any remain.
7. **Test (manual):** `bash chezmoi/.chezmoiscripts/run_onchange_25-install-curl-toolchains.sh` in dry-run mode (DRY_RUN=1 env var) prints intended actions without executing curls. (Implementer: add `if [[ -n "${DRY_RUN:-}" ]]; then log_info "would: $*"; return; fi` wrapper.)

### Task 2 — macOS defaults

1. `chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh` exists and is executable.
2. The hook applies the **sensible-defaults baseline** below, grouped by domain. Each `defaults write` is idempotent (rerunning is a no-op).
3. After all writes, hook runs `killall Dock Finder SystemUIServer 2>/dev/null || true` to make changes visible.
4. Hook prints `log_ok` summary at the end with count of keys applied.
5. `scripts/scan-macos-defaults.sh` exists, is executable, and:
   - Reads current `defaults read` values for the same keys the hook writes.
   - Prints them in a format that can be **copy-pasted into the hook** (i.e. `defaults write <domain> <key> -<type> <current-value>`).
   - Optionally accepts `--diff` flag to compare current vs hook baseline and print only divergent keys.
6. `bootstrap.sh` adds a `scan-macos` subcommand routed to `scripts/scan-macos-defaults.sh`. Menu entry: `scan-macos — print current System Settings as defaults write commands`.
7. **Test (manual):** running the hook on a fresh Mac and rebooting → Dock is autohide+small, Finder shows hidden files + extensions + path bar, screenshots land in `~/Pictures/Screenshots` with no shadow, key-repeat is fast.

### Task 3 — Documentation

1. `README.md` "Subcommands" section gains `scan-macos` row.
2. `docs/usage.md` gains two short subsections (under existing "chezmoi hooks" or similar): one describing the curl-toolchains hook (what it installs, idempotency, how to rerun), one describing the macOS defaults hook + scan helper.
3. No false claims that Plan 2/3 are done.

## Sensible-defaults baseline (referenced by Task 2 hook)

```bash
# ── Dock ──
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.2
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock minimize-to-application -bool true

# ── Finder ──
defaults write -g AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"   # list view
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder WarnOnEmptyTrash -bool false
defaults write NSGlobalDomain AppleShowAllFiles -bool true
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true   # no .DS_Store on network shares

# ── Screenshots ──
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture include-date -bool true

# ── Keyboard ──
defaults write -g KeyRepeat -int 2
defaults write -g InitialKeyRepeat -int 15
defaults write -g ApplePressAndHoldEnabled -bool false   # repeat instead of accent menu
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false

# ── Trackpad ──
# tap-to-click disabled — prefer physical click everywhere
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool false
defaults write -g com.apple.mouse.tapBehavior -int 0
defaults write -g com.apple.trackpad.scaling -float 1.5

# ── UI ──
defaults write -g NSWindowResizeTime -float 0.001
defaults write -g NSScrollAnimationEnabled -bool false
defaults write -g NSWindowShouldDragOnGesture -bool true
defaults write com.apple.LaunchServices LSQuarantine -bool false   # no "are you sure you want to open?"

# ── Safari (dev-friendly) ──
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
```

That's ~35 keys covering the highest-value daily ergonomics. User can extend later via `scan-macos`.

## Open questions

None. All ambiguities resolved during Phase 0 batched clarification.

## Test plan (manual, on this Mac)

- Curl-toolchains hook: backup `~/.oh-my-zsh` to `~/.oh-my-zsh.bak`, run hook, confirm restore works.
- macOS defaults hook: run, confirm Dock autohide kicks in, Finder shows hidden files, screenshots go to `~/Pictures/Screenshots`. Revert via `defaults delete` for any unwanted keys.
- Re-run both hooks twice — both must print "already installed" / "no changes" on the second run.
