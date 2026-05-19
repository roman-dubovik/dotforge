# dotforge roadmap

_Last updated: 2026-05-19_

No ETAs. Order within a section is rough priority, not a commitment.

## Where we are

dotforge is a chezmoi-powered macOS bootstrap framework with CLI automation. Starting from a fresh Mac, it installs Xcode Command Line Tools, Homebrew, and deploys declarative dotfiles (shell config, packages, SSH keys, login items, macOS defaults) via chezmoi templates. The `dot` CLI provides idempotent operations: `dot doctor` for diagnostics, `dot apply` for config sync (with `--enable/--disable` flag toggles), `dot snapshot` for cross-machine capture, `dot pull` (`--resolve=ours/theirs/interactive/abort`) for fetching + applying updates, `dot status` for non-destructive divergence reports, and `dot features` for listing toggle state. Six feature flags control software categories; four archetypes (full / minimal-dev / cli-server / custom) pre-shape the install experience. Three scanners (CLI globals, login items, macOS defaults) feed git-mediated cross-machine sync.

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
- **65 new bats tests** across `tests/lib/state.bats` (34), `tests/scripts/dot-apply-features.bats` (18), `tests/scripts/dot-features.bats` (13).
- **Out of scope for this slice:** the `local_llm` feature flag (originally listed alongside 2e) remains deferred — see "What's next" below; it's blocked on ollama landing in the Brewfile.

## Architectural vision (where the framework is heading)

dotforge today snapshots three things (CLI globals, login items, macOS defaults) into single shared files in the repo root. That's enough for one Mac, but it falls apart once you have a Mac mini, a work laptop, and a personal MacBook — each machine has a different set of installed apps, different login items, different keyboard repeat rates. Last machine to `dot snapshot` wins; everything else loses.

The framework is moving toward a **per-machine baseline + composable overlays** model:

1. **Per-machine snapshot baseline.** Each machine writes to its own `machines/<machine_name>/` subtree in the repo: `machines/mac-mini/cli-globals.txt`, `machines/work-laptop/macos-defaults.txt`, etc. `dot snapshot` only touches the current machine's folder. `dot apply` reads from `machines/{{ .machine_name }}/...`. Mac mini and work laptop coexist in the same repo without overwriting each other. From any machine's snapshot you can spin up a new Mac in the same state by running bootstrap with `--from-machine=mac-mini`.

2. **Composable archetypes (decoupled from machines).** Today's archetypes (`full` / `minimal-dev` / `cli-server` / `custom`) are single-choice presets that only shape the Brewfile at init. Future archetypes become **reusable overlays** living in `archetypes/<name>/extra-brewfile.txt`, `extra-cli-globals.txt`, `extra-macos-defaults.txt`. A machine's `.chezmoi.toml` lists `archetypes = ["dev-frontend", "ml-research", "media-creator"]` — `dot apply` unions them on top of that machine's baseline. **One machine can carry every archetype it needs at once**, rather than being locked to one preset at init time.

3. **Expanded scanner coverage.** Today three scanners (CLI globals, login items, macOS defaults). Adding scanners for AI tool configs, shell config drift, oh-my-zsh plugins, and toolchain versions closes the gap between "what dotforge automates" and "what users keep tweaking by hand."

The roadmap below is sequenced around this vision: per-machine layout first (because every new scanner needs it), then richer scanners, then composable archetypes.

## What's next

### ~~🟢 1. Slice 2e — Programmatic flag toggles~~ ✅ Shipped 2026-05-18

~~Enable / disable features from command line: `dot apply --enable=docker_desktop --disable=office_suite`. Persist menu state across runs (bootstrap.sh customize answers stored in chezmoi.toml). Removes manual edit of feature sections in prompts.~~

### ~~🟢 2. Plan 3 MVP — Multi-machine reconciliation~~ ✅ Shipped 2026-05-18

~~Active sync with conflict resolution: when two machines diverge (one installs a new app, the other upgrades brew), `dot pull` on the second machine detects the delta and merges intelligently. Currently sync is git-mediated (push `dot snapshot`, pull on other machine) — no active three-way merge.~~

**Shipped:** `dot status` (non-destructive divergence report) + `dot pull --resolve=ours|theirs|interactive|abort` (stash-merge-pop conflict resolution). Three-way merge is the next step (see below).

### 🟡 2b. Plan 3 — Full three-way merge

Polished three-way merge for scanner output files: instead of `--ours`/`--theirs`, diff both sides against the common ancestor and produce a merged result automatically. Required for the case where two machines both add different new items to `cli-globals.txt` without any shared lines conflicting. **Becomes simpler once per-machine baselines (§4) land**, because most cross-machine conflicts disappear: Mac mini edits `machines/mac-mini/cli-globals.txt`, work laptop edits `machines/work-laptop/cli-globals.txt`, no shared file = no conflict.

### 🟡 2c. `local_llm` feature flag (deferred from 2e)

Add a seventh feature flag `local_llm` toggling local LLM packages (ollama + suggested models + optional open-webui). Originally bundled with Slice 2e — descoped because none of the LLM packages are in `Brewfile.tmpl` yet. Real prerequisite: decide on an ollama bundle (`ollama` + which models? `open-webui` cask?) and add to the Brewfile under the new flag. Once present, surfaces in `dot features` and `dot apply --enable=local_llm` automatically.

### 🟡 3. `scan-ai-config` — Claude / Codex / Gemini CLI configs

Fourth scanner that captures AI tool configuration from the local machine into the repo. Covers:

- **Claude Code** — `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/keybindings.json`
- **OpenAI Codex CLI** — `~/.codex/config.toml` (explicitly skips `~/.codex/auth.json` and any `*.token` / `credentials*` files)
- **Gemini CLI** — `~/.gemini/settings.json`, `~/.gemini/GEMINI.md`

Capture model: files copied wholesale via `chezmoi add` into the repo source tree (`machines/<machine_name>/dot_claude/`, `machines/<machine_name>/dot_codex/`, etc. once §4 lands; until then, into shared `chezmoi/dot_claude/` etc.). Auth files filtered by deny-list before capture; never committed. On `chezmoi apply`, files restored 1:1 to the user's home directory. Integrates into `dot snapshot` as a fourth `--capture` pass, and into `dot doctor` as a drift check.

**Not in scope for v1:** Cursor, Aider, Continue.dev, GitHub Copilot CLI. Adding those later just means extending the path list; the scanner pattern stays the same.

### 🟡 4. Per-machine snapshot baselines

Refactor the three existing scanners (and `scan-ai-config` from §3) to write into `machines/<machine_name>/` subdirectories. The current shared files (`cli-globals.txt`, `chezmoi/dot_config/dotforge/macos-defaults.txt`, `login-items.txt`) move under `machines/<machine_name>/`. Chezmoi hooks (`run_onchange_30-install-cli-globals.sh.tmpl`, `run_onchange_60-apply-macos-defaults.sh.tmpl`, `run_onchange_70-apply-login-autostart.sh`) read the current machine's variant via `{{ .machine_name }}`. `dot pull --resolve` becomes trivially conflict-free across machines that touch different subtrees.

Includes a one-shot migration: first `dot apply` on an existing repo after the upgrade moves shared files into `machines/<machine_name>/` and leaves a stub readme explaining the new layout. Backward-compatible read path: if `machines/<name>/` is missing, hooks fall back to the old shared file (with a deprecation warning).

### 🟡 5. Composable archetypes (overlays)

Archetypes evolve from single-choice init presets into reusable layers stored under `archetypes/<archetype_name>/`. Each archetype is a directory containing any of `extra-brewfile.txt`, `extra-cli-globals.txt`, `extra-macos-defaults.txt`, `extra-login-items.txt`, `extra-ai-config/`. The machine's `~/.config/dotforge/state.toml` gains an `[archetypes]` section listing applied overlays. `dot apply` unions all applied archetypes on top of the machine baseline. New CLI: `dot archetype add dev-frontend`, `dot archetype remove ml-research`, `dot archetype list`.

Migration: existing four archetypes (`full` / `minimal-dev` / `cli-server` / `custom`) become seed overlays — `full` is equivalent to applying every other overlay; `minimal-dev` and `cli-server` become starting points users can extend. The single archetype prompt at init becomes a multi-select.

### 🟡 6. `scan-shell-config` — drift report (not auto-promote)

Compare the user's live `~/.zshrc` against the chezmoi template `private_dot_zshrc.tmpl` after applying it, surface any aliases / exports / sourced files the user added by hand. **Reports drift, does not promote** — template-aware auto-merge is hard and unsafe; user manually decides which additions to fold back into the template. Surfaces in `dot doctor` as a new check, and in `dot status` as an additional divergence signal.

### 🟡 7. `scan-omz` / `scan-nvm` / `scan-pnpm` — toolchain version capture

Capture the resolved versions and plugin lists for shell / runtime managers that today are pinned by hand in `run_onchange_25-install-curl-toolchains.sh`:

- `scan-omz` — enabled oh-my-zsh plugins from `~/.oh-my-zsh/custom/plugins/` and the `plugins=(...)` array in `~/.zshrc`
- `scan-nvm` — current default Node version from `nvm alias default` plus list of installed versions
- `scan-pnpm` — pinned pnpm version from `package.json` `packageManager` field or `~/.local/share/pnpm/`
- `scan-omz` writes a manifest the install hook then replays via `omz plugin enable`

Each is a small scanner producing a single manifest file under `machines/<machine_name>/`. Replays through the existing toolchains hook with version pins applied.

### 🟡 8. App-specific configs

Persist declarative configs for Raycast, VS Code, JetBrains IDEs, Hammerspoon, Rectangle. Extend scanner output to include app-specific plist dumps and rehydrate via `dot apply`. Same model as `scan-ai-config` but per app — copy known config paths into `machines/<machine_name>/`, filter cache / log / token files via deny-list. Likely shipped one app at a time rather than as a single mega-slice.

### ⚪ 9. Browser & email logins

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

1. **`dot config` editor?** — `state.toml` is now the persistence layer for feature flags. Should we expose a `dot config edit` command (open `$EDITOR` on the file) or keep mutations exclusively through `dot apply --enable/--disable`?
2. **Per-machine subtree layout** — `machines/<machine_name>/` is the proposed shape, but: do we also move `chezmoi/Brewfile.tmpl` under it, or is Brewfile shared across all of a user's Macs (current assumption)? Argument for shared: most users want the same brew set everywhere. Argument for per-machine: a Mac mini server doesn't need design tools that a MacBook designer needs. Likely answer: keep Brewfile shared at root, use feature flags + archetypes (§5) for per-machine variance.
3. **Archetype = overlay vs identity?** — §5 makes archetypes composable overlays applied on top of a machine baseline. But for first-time init, do we still ask "pick an archetype" (and that seeds the overlay list), or just "pick zero or more archetypes"? Affects bootstrap.sh UX heavily.
4. **AI config secrets hygiene** — `scan-ai-config` filters obvious auth files (`auth.json`, `*.token`, `credentials*`). But Claude `settings.json` can contain Bedrock/Vertex API keys; some user-added skills may embed tokens. Should we scan captured files for high-entropy strings and refuse to commit by default? Or trust user to review the snapshot diff?
5. **Plan 3b three-way merge strategy** — For full three-way merge on scanner output files: apply per-section, per-line, or per-file? Once per-machine subtrees (§4) land, most conflicts disappear; remaining cases (two machines both editing the same `archetypes/<name>/extra-brewfile.txt`) need a strategy.
6. **Which feature flags next?** After `docker_desktop`, `ai_assistants`, `vpn_suite`, should we add more granular flags (`postgres`, `node_toolchain`, `ruby_toolchain`) or keep the current six? Tradeoff: more flags = more choice, but more prompts and harder testing surface. **Becomes less urgent if composable archetypes (§5) land** — archetypes can subsume the granularity.
