# roman-dubovik/dotforge

Personal Mac bootstrap. One command on a fresh Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

## What it does

1. Installs Xcode Command Line Tools
2. Installs Homebrew
3. Installs CLI tools and GUI apps from `Brewfile`
4. Installs curl-based toolchains: oh-my-zsh, powerlevel10k, zsh plugins, nvm + Node LTS, pnpm, maestro
5. Replays CLI globals (npm/pnpm/cargo/go/pip) from `cli-globals.txt`
6. Sets up dotfiles (`.zshrc`, `.gitconfig`, `~/.ssh/config`) via [chezmoi](https://chezmoi.io)
7. Restores SSH keys from Bitwarden (item: `dotforge-ssh-<profile>`)
8. Applies login items and loads custom LaunchAgents from `~/Library/LaunchAgents/`
9. Applies macOS system defaults (Dock, Finder, Keyboard, Screenshots, Trackpad, Safari)

Takes ~15-20 minutes on a clean machine.

## Subcommands

Run `bootstrap.sh` with one of these subcommands:

- `setup` — full Mac bootstrap
- `update` — chezmoi update + apply
- `sync` — promote local extras into the canonical Brewfile
- `customize` — re-pick Brewfile sections
- `add-key` — upload SSH keys to Bitwarden (bulk or single)
- `scan-cli` — classify everything in PATH; capture globals
- `scan-macos` — print current macOS System Settings as `defaults write` commands
- `scan-autostart` — dump current login items + LaunchAgents survey
- `doctor` — read-only sync check: 8 diagnostic checks against canonical state, exits 0/1/2
- `fork` — clone+personalize this repo under your own GitHub
- `browse` — read-only walkthrough

## Profiles

- `personal` — your own Macs
- `work` — corporate Macs (uses different SSH keys, git email)

## Bitwarden secrets

The bootstrap reads SSH keys from Bitwarden items named:

- `dotforge-ssh-personal` — attachments: `id_ed25519_personal` + `.pub`
- `dotforge-ssh-work` — same for work

Each item has custom fields: `profile`, `created_at`, `fingerprint`, `algorithm`.

## Roadmap

**Plan 1 — Bootstrap baseline** (done) — Xcode CLT, Homebrew, Brewfile, dotfiles via chezmoi, SSH keys from Bitwarden, Claude config, `fork` subcommand for reuse.

**Plan 1.5 — Closing the manual-step gap** (done) — Curl-toolchains hook (oh-my-zsh, p10k, nvm + Node LTS, pnpm, maestro, zsh plugins), macOS defaults hook (~35 keys across Dock/Finder/Screenshots/Keyboard/Trackpad/UI/Safari), `scan-macos` subcommand for snapshotting current state.

**Plan 2 (in progress) — `dot doctor` shipped; persistent archetypes + `dot apply/snapshot/pull` + feature flags pending**:
- `bootstrap.sh doctor` — 8-check read-only diagnostic (chezmoi state, Brewfile, CLI globals, curl-toolchains, SSH keys, macOS defaults, login items, repo sync) — **done**.
- Persistent archetypes (dev-machine / media / ops-server) stored in `chezmoi.toml`, applied on every `update`. Today `scripts/customize-brewfile.sh` offers `full` / `minimal-dev` / `cli-server` / `custom` as a runtime choice, but the choice isn't remembered between machines or apply runs.
- `dot` CLI wrapper with `apply` / `snapshot` / `pull` subcommands as a unified interface over chezmoi + brew + macOS state.
- Feature flags (toggle docker-desktop / jetbrains / local-llm) declared inside archetypes.

**Plan 3 — Multi-machine sync** (pending) — active reconciliation between machines (e.g. detecting that mac-mini has a brew package mbp doesn't, or that one Mac drifted from the canonical state) with conflict resolution. Today distribution is one-way via chezmoi + git; two-tier Bitwarden items (`dotforge-ssh-<profile>` vs `dotforge-ssh-<profile>-<machine>`) handle key scoping but not state reconciliation.

**Config sync gaps** (un-numbered, considered for Plan 1.5+):
- App-specific configs not auto-restored: Raycast, VS Code / Cursor settings + extensions, JetBrains plugins, iTerm / Warp / Ghostty profiles, Hammerspoon, Rectangle / BetterDisplay
- Browser extensions, mail accounts, app subscription logins — manual by Apple-platform constraints

## Using this for your own Mac

This repo is designed to be forked and personalized for your GitHub account, name, and email.

The `bootstrap.sh fork` subcommand automates the entire process:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash -s -- fork
```

This command:
1. Clones the repo to a directory you choose
2. Runs `personalize-fork.sh`, which finds and replaces:
   - `roman-dubovik/dotforge` → your GitHub repo
   - `Roman Dubovik` → your name
   - `booroman@gmail.com` → your email
   - `id_ed25519_github_booroman` → `id_ed25519` (optional, via `--reset-ssh`)
3. Walks you through each change with confirmation prompts
4. Offers to create the new repo on your GitHub and push

Note: The Bitwarden item prefix `dotforge-ssh-*` is not user-configurable in the fork script. The work-profile email placeholder in `chezmoi/dot_gitconfig.tmpl` requires manual edit post-fork if you use a work profile.
