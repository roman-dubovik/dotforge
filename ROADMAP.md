# dotforge roadmap

_Last updated: 2026-05-18_

No ETAs. Order within a section is rough priority, not a commitment.

## Where we are

dotforge is a chezmoi-powered macOS bootstrap framework with CLI automation. Starting from a fresh Mac, it installs Xcode Command Line Tools, Homebrew, and deploys declarative dotfiles (shell config, packages, SSH keys, login items, macOS defaults) via chezmoi templates. The `dot` CLI provides idempotent operations: `dot doctor` for diagnostics, `dot apply` for config sync, `dot snapshot` for cross-machine capture, and `dot pull` for fetching + applying updates. Six feature flags control software categories; four archetypes (full / minimal-dev / cli-server / custom) pre-shape the install experience. Three scanners (CLI globals, login items, macOS defaults) feed git-mediated cross-machine sync.

## Shipped

### Foundation (2026-04)

- **Xcode CLT, Homebrew, brew bundle** — automated install path, Brewfile template.
- **chezmoi dotfiles baseline** — shell config, SSH key pull from Bitwarden, login item scripting.
- **macOS defaults baseline** — system settings applier via `defaults write`.
- **`bootstrap.sh fork`** — personalize-for-own-account flow.

### The `dot` namespace (2026-05-07)

- **`dot doctor`** — read-only sync check: 8 diagnostics (`chezmoi`, `brewfile`, `cli-globals`, `curl-toolchains`, `ssh-keys`, `macos-defaults`, `login-autostart`, `repo`).
- **`dot` CLI shim** — chezmoi-managed executable in `~/.local/bin/dot`, routes subcommands to shell functions.
- **Command stubs** — `help`, `version`.

### Loop-closing + flags (2026-05-16 to 2026-05-17)

- **`dot apply`** — chezmoi apply + before/after doctor delta, `--dry-run` mode, idempotent re-runs.
- **`dot snapshot`** — scan-cli + scan-login + scan-macos capture → auto-commit to git (with diffs).
- **`dot pull`** — fetch + ff-only + `chezmoi apply` + `dot doctor` (exit code propagated; no before/after delta — use `dot apply` for that).
- **Six feature flags** — `docker_desktop`, `ai_assistants`, `vpn_suite`, `office_suite`, `media_tools`, `design_tools` (via `chezmoi/.chezmoi.toml.tmpl` `[data.features]`).
- **Full macOS capture** — `scan-macos-defaults.sh --capture` persists to `chezmoi/dot_config/dotforge/macos-defaults.txt`; `chezmoi apply` rehydrates.
- **bats test suite** — feature-flag toggles, scanner output validation, apply/pull/doctor semantics.

### Slice 2e — Programmatic feature toggles (2026-05-18)

- **`dot apply --enable/--disable`** — toggle feature flags programmatically: `dot apply --enable=docker_desktop --disable=office_suite,media_tools`. Supports CSV or repeated flags. Unknown flags exit 2 with a listing of valid names.
- **`dot features`** — list all six flags with current value, source (`state.toml` / `chezmoi.toml` / `default`), and `in-sync` / `DIVERGENT` status.
- **`~/.config/dotforge/state.toml`** — dedicated state file for CLI-driven mutations, kept in sync with `~/.config/chezmoi/chezmoi.toml`.
- **`bootstrap.sh customize` integration** — defaults now read from `state.toml` first (priority: `state.toml` > `chezmoi.toml` > hardcoded default); selections saved back to `state.toml`.
- **51 new bats tests** across `tests/lib/state.bats`, `tests/scripts/dot-apply-features.bats`, `tests/scripts/dot-features.bats`.

## What's next

### ~~🟢 1. Slice 2e — Programmatic flag toggles~~ ✅ Shipped 2026-05-18

~~Enable / disable features from command line: `dot apply --enable=docker_desktop --disable=office_suite`. Persist menu state across runs (bootstrap.sh customize answers stored in chezmoi.toml). Removes manual edit of feature sections in prompts.~~

### ~~🟢 2. Plan 3 MVP — Multi-machine reconciliation~~ ✅ Shipped 2026-05-18

~~Active sync with conflict resolution: when two machines diverge (one installs a new app, the other upgrades brew), `dot pull` on the second machine detects the delta and merges intelligently. Currently sync is git-mediated (push `dot snapshot`, pull on other machine) — no active three-way merge.~~

**Shipped:** `dot status` (non-destructive divergence report) + `dot pull --resolve=ours|theirs|interactive|abort` (stash-merge-pop conflict resolution). Three-way merge is the next step (see below).

### 🟡 2b. Plan 3 — Full three-way merge

Polished three-way merge for scanner output files: instead of `--ours`/`--theirs`, diff both sides against the common ancestor and produce a merged result automatically. Required for the case where two machines both add different new items to `cli-globals.txt` without any shared lines conflicting.

### 🟡 3. App-specific configs

Persist declarative configs for Raycast, VS Code, JetBrains IDEs, Hammerspoon, Rectangle. Extend scanner output to include app-specific plist dumps and rehydrate via `dot apply`.

### ⚪ 4. Browser & email logins

Capture browser autofill profiles, email accounts, and app authentication tokens. Limited by Apple sandboxing — Safari keychain and Mail account store are not directly accessible via shell. Requires either user manual export or third-party credential managers (1Password, Dashlane via their CLIs if installed).

## Deferred / non-goals

- **Linux / Windows support** — dotforge is macOS-only. The entire philosophy (Homebrew, chezmoi, macOS defaults via `defaults write`) is Darwin-specific.
- **Full GUI app state restore** — capturing frame positions, window layouts, app-specific UI state across 500+ macOS apps is unbounded and brittle. Solved piecemeal by app-specific configs (see §3 above).
- **App Store purchased app sync** — App Store apps cannot be freely redistributed or listed in Brewfile; user must install from App Store manually.
- **Graphical UI installer** — No native Cocoa app or web UI. `bootstrap.sh` is shell-driven with TTY prompts; GitHub Pages landing is informational only.
- **VCS fallback to something other than git** — All sync assumes git + GitHub. No Mercurial, Fossil, or plain-HTTP mirrors.

## Known limits (honest)

- **macOS-only.** Requires Darwin kernel, zsh/bash, curl, brew, git, chezmoi, Bitwarden CLI.
- **Requires Bitwarden.** SSH keys are retrieved at runtime via `bw get`. No fallback to 1Password, Dashlane, or plain-text files.
- **Requires Homebrew.** All package management goes through `brew` and `brew bundle`. GNU/Linux package managers not supported.
- **Conflict resolution is strategy-based, not three-way.** `dot pull --resolve=ours/theirs` picks a side; full three-way merge (Plan 3b) is not yet implemented. `dot status` helps detect divergence before pulling.
- **Some apps require manual restore.** IDE settings, Hammerspoon config, browser extensions — each has its own backup strategy. dotforge covers shell config, system defaults, Brewfile, login items, and SSH keys; beyond that, user must export / restore app-specifically or rely on iCloud / cloud-sync where available.
- **Apple sandboxing blocks certain captures.** Safari keychain, Mail accounts, and system credentials in Keychain are not shell-accessible without full-disk-access entitlements (and even then, Keychain APIs require Objective-C). Bitwarden is the workaround.

## Open questions

1. **Persistent bootstrap menu** — Should `bootstrap.sh customize` store answers in chezmoi.toml so that repeat runs default to previous choices? Or keep it stateless (requires re-entry each time)?
2. **Multi-machine conflict resolution strategy** — When two machines diverge (one has a newer brew formula, the other has a local app), should `dot pull` do a three-way merge (git-like), a "last-write-wins" squash, or fail with a manual-resolve prompt?
3. **Archetype migration** — After initial bootstrap with `full` archetype, can user switch to `minimal-dev` (removing docker, media tools)? Or is archetype immutable once set? If mutable, how do we track "installed by archetype" vs "manually installed"?
4. **Which feature flags next?** After `docker_desktop`, `ai_assistants`, `vpn_suite`, should we add more granular flags (`postgres`, `node_toolchain`, `ruby_toolchain`) or keep the current six? Tradeoff: more flags = more choice, but more prompts and harder testing surface.
