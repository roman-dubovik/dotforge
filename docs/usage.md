# dotforge — Usage Guide

End-to-end usage and operations reference for the
[roman-dubovik/dotforge](https://github.com/roman-dubovik/dotforge) bootstrap.

## Contents

1. [Quick start (fresh Mac)](#quick-start-fresh-mac)
2. [Prerequisites](#prerequisites)
3. [What the bootstrap does](#what-the-bootstrap-does)
4. [Interactivity](#interactivity)
5. [Customizing the Brewfile](#customizing-the-brewfile)
6. [Promoting machine extras back into the canonical Brewfile](#promoting-machine-extras-back-into-the-canonical-brewfile)
7. [CLI globals (npm, pnpm, cargo, go, pip)](#cli-globals-npm-pnpm-cargo-go-pip)
8. [Forking this repo for yourself](#forking-this-repo-for-yourself)
9. [Profiles](#profiles)
10. [Daily operations](#daily-operations)
11. [Adding or rotating SSH keys](#adding-or-rotating-ssh-keys)
12. [Editing dotfiles](#editing-dotfiles)
13. [Managing Bitwarden secrets](#managing-bitwarden-secrets)
14. [Repository layout](#repository-layout)
15. [chezmoi naming conventions](#chezmoi-naming-conventions)
16. [Troubleshooting](#troubleshooting)
17. [What is not yet covered](#what-is-not-yet-covered)

---

## Quick start (fresh Mac)

On a clean macOS install, open Terminal and run a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

The script first installs the minimum needed to render its own menu (Xcode
CLT, Homebrew, gum), then shows a top-level menu:

```
What would you like to do?
  > setup     — Set up this Mac (full bootstrap)
    update    — Pull latest dotfiles from remote and re-apply
    sync      — Promote local extras (brew + /Applications) into Brewfile
    customize — Re-pick which Brewfile sections to install
    add-key   — Upload a new SSH key to Bitwarden (profile or machine scope)
    scan-cli  — Classify everything in PATH; capture CLI globals
    fork      — Make your own dotforge for a different GitHub account
    browse    — Read-only walkthrough of what's available
    exit      — Quit
```

For a brand-new Mac, pick **setup** — it walks you through:

1. **Bootstrap dependencies** — installs `chezmoi`, `bitwarden-cli`, `yq`, `gum`.
2. **Machine name** (`gum input`) — short, human-friendly identifier; default
   is the machine's `LocalHostName`.
3. **Profile** (`gum choose`) — `personal` or `work`. Determines git email,
   SSH key names, and any profile-conditional dotfile blocks.
4. **Bitwarden login** (`bw login` / `bw unlock`) — master password (and 2FA
   if your account uses it). Vault is locked again on script exit via trap.
5. **Brewfile customizer** (optional, `gum confirm` defaults to Yes) — pick
   archetype, fine-tune sections, preview, write `Brewfile.local`. See
   [Customizing the Brewfile](#customizing-the-brewfile).
6. **chezmoi apply** — installs dotfiles, runs the Brewfile and SSH-keys
   hooks.

Total time on a clean machine: ~15–20 minutes (most of it is Homebrew + cask
downloads).

After completion, **restart your shell** (open a new tab in iTerm/Terminal) so
the new `~/.zshrc` is sourced.

### Skipping the menu (direct subcommands)

You can pass the action as an argument to skip the menu:

```bash
bootstrap.sh setup                   # full bootstrap
bootstrap.sh update                  # chezmoi update + apply
bootstrap.sh sync                    # run scripts/sync-brewfile.sh
bootstrap.sh customize               # run scripts/customize-brewfile.sh
bootstrap.sh add-key id_ed25519_x    # upload an SSH key to Bitwarden
bootstrap.sh scan-cli                # PATH classifier (brew/npm/pnpm/...)
bootstrap.sh scan-cli --capture      # write cli-globals.txt for replay on fresh Mac
bootstrap.sh fork --gh-user friend   # clone+personalize for another account
bootstrap.sh browse                  # read-only walkthrough
bootstrap.sh --help                  # show this list
```

The same applies if you `curl ... | bash` — append `bash -s -- <subcommand>`:

```bash
curl -fsSL https://.../bootstrap.sh | bash -s -- update
```

### What "browse" shows

A read-only walkthrough that works even before `setup` (uses the cloned repo
if available, falls back to `curl` from raw.githubusercontent.com):

- Canonical `Brewfile` (via `gum pager`)
- Current chezmoi state: profile, machine_name, active Brewfile, bw status
- List of managed dotfiles (`chezmoi/dot_*`, `chezmoi/private_dot_*`)
- Each chezmoi script hook content
- This `docs/usage.md` document
- Open the GitHub repo in your default browser

---

## Prerequisites

- macOS 14+ (Apple Silicon or Intel)
- A working internet connection
- A Bitwarden account that already contains a `dotforge-ssh-<profile>` item
  (see [Adding or rotating SSH keys](#adding-or-rotating-ssh-keys) for how to
  populate it)
- For the active GitHub flow during bootstrap (only relevant if you push
  yourself the same hour): a `gh auth login` already done in this account

The bootstrap installs everything else (Xcode CLT, Homebrew, chezmoi, bw, gum,
yq, the Brewfile contents).

---

## What the bootstrap does

`bootstrap.sh` runs in this strict order:

1. **Pre-flight checks** — verifies macOS and supported architecture
   (arm64 / x86_64); aborts otherwise.
2. **Xcode Command Line Tools** — runs `xcode-select --install` and waits
   until the installer finishes (idempotent if already present).
3. **Homebrew** — installs Homebrew non-interactively
   (`NONINTERACTIVE=1`) and sets up `brew shellenv` for the current session.
4. **Bootstrap dependencies** — `chezmoi`, `bitwarden-cli`, `yq`, `gum`. These
   are needed before chezmoi can take over.
5. **Interactive prompts (gum)** — collects `machine_name` and `profile`.
6. **Bitwarden login** — `bw login --raw` (or `bw unlock --raw` if already
   logged in) captures the session into `BW_SESSION`. An `EXIT` trap calls
   `bw lock` so the vault is sealed when bootstrap finishes (success or
   failure).
7. **chezmoi init** — clones `roman-dubovik/dotforge` to
   `~/.local/share/chezmoi`, reads `.chezmoiroot` to find the `chezmoi/`
   subdirectory as the source, generates `~/.config/chezmoi/chezmoi.toml`
   from `.chezmoi.toml.tmpl` (using the prompt values). Does **not** apply
   yet.
8. **Brewfile customizer** (optional, default Yes) — `gum confirm` offers
   to run `scripts/customize-brewfile.sh`, which lets you pick an archetype
   (`full` / `minimal-dev` / `cli-server` / `custom`), optionally fine-tune
   sections, preview each before installing, and writes `Brewfile.local`.
   See [Customizing the Brewfile](#customizing-the-brewfile) for details.
9. **chezmoi apply** — applies dotfiles and runs the script hooks:
   - `run_once_before_10-install-bw.sh` — guarantees `bitwarden-cli` and `yq`
     even if Brew is in an odd state (idempotent).
   - `run_onchange_20-apply-brewfile.sh.tmpl` — runs `brew bundle install`,
     using `Brewfile.local` if it exists (from step 8) and falling back to
     the canonical `Brewfile` otherwise. Re-runs when the chosen Brewfile's
     content or profile changes.
   - `run_onchange_50-pull-ssh-keys.sh.tmpl` — restores SSH keys from
     Bitwarden into `~/.ssh/`.
10. **Done message** — bootstrap reminds you to restart your shell.

---

## Interactivity

Interactivity is wired at three layers:

| Layer | Tool | Where | What it asks |
|---|---|---|---|
| Bootstrap | `gum input` | `bootstrap.sh` | Machine name (default = `LocalHostName`) |
| Bootstrap | `gum choose` | `bootstrap.sh` | Profile: `personal` or `work` |
| Bootstrap | `gum confirm` | `bootstrap.sh` | Whether to customize the Brewfile (Yes/No) |
| Bootstrap | `bw login` / `bw unlock` | `bootstrap.sh` | Bitwarden email + master password (+ 2FA) |
| Customizer | `gum choose` | `scripts/customize-brewfile.sh` | Archetype: `full` / `minimal-dev` / `cli-server` / `custom` |
| Customizer | `gum choose --no-limit` | `scripts/customize-brewfile.sh` | Per-section toggle (when fine-tuning or `custom`) |
| Customizer | `gum checkbox` | `scripts/customize-brewfile.sh` | Feature flags toggle (docker, AI, VPN suite, etc.) |
| Customizer | `gum pager` | `scripts/customize-brewfile.sh` | Preview a section's content before installing |
| Customizer | `gum confirm` | `scripts/customize-brewfile.sh` | Confirm install |
| Xcode CLT | macOS native dialog | OS-managed | License acceptance |
| chezmoi | `promptStringOnce` | `.chezmoi.toml.tmpl` | Same `machine_name`, only fires if `bootstrap.sh` skipped |
| chezmoi | `promptChoiceOnce` | `.chezmoi.toml.tmpl` | Same `profile`, only fires if `bootstrap.sh` skipped |

See [Customizing the Brewfile](#customizing-the-brewfile) below for the full
customizer flow.

Things deliberately **not interactive**:

- Once the customizer writes `Brewfile.local`, the chezmoi hook applies it
  without further prompts. The customizer is the one place to opt out.
- SSH-key restoration silently skips if Bitwarden is locked (it logs a warning
  and exits 0, so the rest of `chezmoi apply` continues). On the next run
  with a valid `BW_SESSION`, the keys download.
- Feature flag toggles (docker, AI assistants, VPN suite, etc.) are handled entirely through the `bootstrap.sh customize` menu — no extra prompts during `chezmoi apply`.

---

## Customizing the Brewfile

The canonical `Brewfile` lists ~86 entries (CLI tools + GUI casks + MAS apps).
On a clean Mac you may want a smaller subset — e.g. for a server VM, a
build-only machine, or a media-only profile. `scripts/customize-brewfile.sh`
generates a `Brewfile.local` (gitignored) from your selection. The chezmoi
brewfile hook prefers `Brewfile.local` over `Brewfile` when both exist, so
the rest of bootstrap is unaffected.

The customizer is offered automatically during `bootstrap.sh` (you can
decline with the `gum confirm` dialog), and can be re-run any time
afterward.

### Archetypes

| Archetype | Sections | Approx. entries |
|---|---|---|
| `full` | All 16 sections | ~86 |
| `minimal-dev` | CLI + Bootstrap + Languages + Cloud + Media docs + Fonts + Browsers + Editors + AI + Dev utilities + Productivity | ~64 |
| `cli-server` | CLI + Bootstrap + Languages + Cloud + Media docs (no GUI, no MAS) | ~45 |
| `custom` | Whatever you pick in the multi-select | varies |

### Interactive run

```bash
~/.local/share/chezmoi/scripts/customize-brewfile.sh
```

Walks you through:

1. **Pick archetype** (`gum choose`).
2. **Fine-tune?** (`gum confirm`) — for non-`custom` archetypes, optional.
   `custom` always opens the multi-select.
3. **Multi-select sections** (if fine-tuning) — `gum choose --no-limit`,
   space toggles, enter confirms. Items are pre-checked based on the
   chosen archetype.
4. **Preview a section?** (loop) — pick a section, opens `gum pager` with
   the literal block content from the canonical `Brewfile`.
5. **Confirm install** — runs `brew bundle install --file=Brewfile.local`
   right away, or skips if you say no.

### Non-interactive run

```bash
~/.local/share/chezmoi/scripts/customize-brewfile.sh \
    --archetype cli-server \
    --no-install \
    --non-interactive
```

Options:

- `--archetype <name>` — `full`, `minimal-dev`, `cli-server`, `custom`.
  In non-interactive mode this is required.
- `--output <path>` — where to write the generated Brewfile (default:
  `<repo-root>/Brewfile.local`).
- `--brewfile <path>` — source Brewfile to read sections from (default:
  `<repo-root>/Brewfile`).
- `--no-install` — write the file but don't run `brew bundle install`.
- `--non-interactive` — skip all prompts; auto-detected when stdin is not
  a TTY.

### Adjusting later

Re-running the customizer overwrites `Brewfile.local`. To roll back to
the canonical Brewfile, just delete `Brewfile.local`:

```bash
rm ~/.local/share/chezmoi/Brewfile.local
chezmoi apply -v   # brewfile hook re-runs, picks up canonical Brewfile
```

### Archetype persistence (chezmoi data var)

Starting with slice 2b, the chosen archetype is stored persistently in
`~/.config/chezmoi/chezmoi.toml` under `[data]`:

```toml
[data]
  brewfile_archetype = "minimal-dev"
```

**When it's prompted:** once during `bootstrap.sh setup` (via `gum choose`
before `chezmoi init`). On subsequent `chezmoi apply` runs on the same
machine it is never re-asked (`promptChoiceOnce` semantics). On a fresh
machine setup, chezmoi prompts for it again.

**Auto-regenerate behavior:** the brewfile hook
(`run_onchange_20-apply-brewfile.sh.tmpl`) applies this logic on every
`chezmoi apply`:

1. If `Brewfile.local` already exists → use it as-is (manual customization
   always wins).
2. Else if archetype is `custom` → fall back to the canonical `Brewfile`
   (no auto-pick; `custom` requires interactive selection).
3. Else → call `customize-brewfile.sh --archetype <name> --no-install` to
   generate `Brewfile.local` from the archetype, then use it.

This means a fresh `chezmoi apply` on a new machine (no `Brewfile.local`)
will automatically produce the correct `Brewfile.local` from the stored
archetype without any user interaction.

**How to change archetype after setup:**

```bash
nvim ~/.config/chezmoi/chezmoi.toml   # change brewfile_archetype = "full"
rm ~/.local/share/chezmoi/Brewfile.local
chezmoi apply                          # hook regenerates Brewfile.local from new archetype
```

### Feature flags

Fine-grained package toggles sit on top of the archetype — they let you keep an archetype's section selection but opt specific packages in or out. Feature values are stored alongside `brewfile_archetype` in `[data.features]` inside `~/.config/chezmoi/chezmoi.toml`.

#### Initial feature set

| Feature | Default | What it controls |
|---|:---:|---|
| `docker_desktop` | true | `cask "docker-desktop"` |
| `ai_assistants` | true | `cask "claude"`, `cask "chatgpt"` |
| `vpn_suite` | true | `cask "tunnelblick"`, `cask "amneziavpn"`, `cask "anydesk"`, `cask "displaylink"`, `cask "termius"`, `cask "windows-app"` |
| `office_suite` | false | `mas "Microsoft Word"`, `mas "Microsoft Excel"`, `mas "Microsoft PowerPoint"` |
| `media_tools` | true | `brew "ffmpeg"`, `brew "yt-dlp"`, `brew "pandoc"`, `brew "tectonic"` |
| `design_tools` | true | `cask "drawio"` |

`office_suite` defaults to false because MAS installs require an Apple ID sign-in — enable it only when you're set up for that.

#### Usage

**Interactive — bootstrap customize menu:**

```bash
bootstrap.sh customize
```

After picking an archetype, the customizer shows a `gum checkbox` menu of all 6 features pre-selected to their current values from `~/.config/chezmoi/chezmoi.toml`. Toggle with space, confirm with enter. `Brewfile.local` is regenerated immediately using your selection.

Fallback when `gum` is not installed: a `y/n` prompt is shown for each feature in sequence.

> **Selection is one-shot, not persisted in slice 2d.** Your toggle choices apply to the regenerated `Brewfile.local`, but the underlying `[data.features]` values in `chezmoi.toml` are NOT updated by this menu. To persist new defaults, edit `~/.config/chezmoi/chezmoi.toml` manually (see below). Programmatic persistence ships in slice 2e.

**Reading current values:**

```bash
grep -A 6 '\[data\.features\]' ~/.config/chezmoi/chezmoi.toml
```

Output example:

```toml
[data.features]
  docker_desktop = true
  ai_assistants = true
  vpn_suite = true
  office_suite = false
  media_tools = true
  design_tools = true
```

**Re-applying after editing `chezmoi.toml` manually:**

```bash
nvim ~/.config/chezmoi/chezmoi.toml   # change e.g. office_suite = true
chezmoi apply --include=scripts -v    # or: dot apply
```

The brewfile hook (`run_onchange_20`) detects the feature change via a content hash in its version comment and re-runs `customize-brewfile.sh --enable=X --disable=Y` automatically.

> **Programmatic toggle (`dot apply --enable=X --disable=Y`) is planned for slice 2e** — currently use the bootstrap customize menu OR edit `chezmoi.toml` manually and re-apply.

### Sections in the canonical Brewfile

The customizer parses sections from `# ── Title ──` headers. The current
sections (Plan 1):

| # | Section | Default in `cli-server` | Default in `minimal-dev` |
|---|---|:---:|:---:|
| 1 | Taps | ✓ | ✓ |
| 2 | CLI essentials | ✓ | ✓ |
| 3 | Bootstrap deps | ✓ | ✓ |
| 4 | Languages / runtimes | ✓ | ✓ |
| 5 | Cloud / dev tooling | ✓ | ✓ |
| 6 | Media / docs | ✓ | ✓ |
| 7 | Fonts | | ✓ |
| 8 | Browsers | | ✓ |
| 9 | Terminals & editors | | ✓ |
| 10 | Dev utilities | | ✓ |
| 11 | AI assistants (desktop) | | ✓ |
| 12 | Productivity / window mgmt | | ✓ |
| 13 | Networking / VPN / remote | | |
| 14 | Communication | | |
| 15 | Utilities | | |
| 16 | Mac App Store apps | | |

The trailing `# ── Manual install ──` block is informational comments only
and is never written to `Brewfile.local`.

---

## Promoting machine extras back into the canonical Brewfile

The other half of "is this machine in sync?" is the *opposite* direction:
you've installed something on a work Mac (Slack, JetBrains IDE, …) that
isn't in the canonical Brewfile, and you want to lift it back so other
machines pick it up on the next `chezmoi update`.
`scripts/sync-brewfile.sh` does this.

### What it does

1. Runs `brew bundle dump` to capture every brew/cask/mas/vscode entry
   currently registered with brew on this machine.
2. Reads the tracked Brewfiles (canonical `Brewfile`, plus `Brewfile.local`
   if you have one).
3. Reports two diffs:
   - **Extras** — installed locally, not in any tracked Brewfile.
   - **Missing** — listed in the Brewfile but not actually installed
     (advisory; the script does not auto-install or auto-remove).
4. For each extra, prompts you (`gum choose`) to promote to:
   - `canonical` — appended to `Brewfile` for everyone, headed by a
     "Promoted from sync-brewfile.sh" marker. You can move them into
     proper `# ── Section ──` headers before committing.
   - `local` — appended to `Brewfile.local` (gitignored, this machine only).
   - `ignore` — skip (it will reappear on the next sync).
5. After promotion, shows `git diff Brewfile` and offers to stage + commit
   in one step. Push manually when ready.

The interactive prompts include each package's description from
`brew desc` (pre-fetched in batch on script start) so you can decide
without alt-tabbing to a browser.

### Run it

```bash
~/.local/share/chezmoi/scripts/sync-brewfile.sh
```

Read-only diff (no prompts, no changes):

```bash
~/.local/share/chezmoi/scripts/sync-brewfile.sh --check
```

Skip noisy categories on a deeply-customized machine:

```bash
~/.local/share/chezmoi/scripts/sync-brewfile.sh --skip-vscode --skip-mas
```

Available flags: `--skip-vscode`, `--skip-mas`, `--skip-tap`, `--check`,
`--non-interactive`, `--brewfile <path>`, `--local <path>`.

### Typical work-Mac flow

```bash
# 1. Bootstrap a work Mac (gets canonical Brewfile + maybe Brewfile.local)
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash

# 2. Use the machine. Install Slack/JetBrains/etc. via brew install --cask
brew install --cask slack jetbrains-toolbox

# 3. Sync: promote the things you'd want on every machine
~/.local/share/chezmoi/scripts/sync-brewfile.sh
# → answers: slack=canonical, jetbrains-toolbox=canonical
# → script appends them to Brewfile, commits, prints "git push when ready"

git -C ~/.local/share/chezmoi push
```

### Caveats

- Apps installed by drag-and-drop into `/Applications` aren't seen by
  `brew bundle dump`. To bring them under brew tracking first:
  `brew install --cask --adopt <name>`. The Adopt flag registers an
  existing app without reinstalling.
- The "Missing" section may be long on this machine because many casks
  in the canonical Brewfile correspond to apps you installed manually
  before adopting them. Either `brew install --cask --adopt` them or
  remove the Brewfile entry.
- VS Code extensions show up by default. If you don't want to manage
  them via Brewfile, pass `--skip-vscode`.

### Where it appends

Promoted entries land at the end of the target file, under a header like:

```
# ── Promoted from sync-brewfile.sh on 2026-05-02 14:30 (canonical) ──
# Move these into the proper section headers above before committing.
cask "slack"
cask "jetbrains-toolbox"
```

Do this housekeeping before pushing — it keeps the canonical Brewfile
organized.

---

## Forking this repo for yourself

If a friend wants to use the same bootstrap pattern under their own GitHub
account — or you want a separate `dotforge-personal` and `dotforge-work`
under the same account — the `fork` subcommand automates it.

### Easy path (interactive)

Either run the public bootstrap and pick `fork` from the menu, or:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash -s -- fork
```

The script will:

1. Ask for a target directory (default `~/Documents/Projects/dotforge-mine`).
2. `git clone --depth=1` this repo into that directory.
3. Hand off to `scripts/personalize-fork.sh`, which:
   - Prompts for your GitHub username, full name, email, and the new repo
     name (default `dotforge`).
   - Replaces `roman-dubovik/dotforge` → `<your-user>/<repo>`,
     `Roman Dubovik` → your name, `booroman@gmail.com` → your email
     across `bootstrap.sh`, `README.md`, `docs/usage.md`,
     `chezmoi/dot_gitconfig.tmpl`, and `LICENSE`.
   - Optionally resets the SSH config's `IdentityFile` example to a
     generic `~/.ssh/id_ed25519` (`--reset-ssh`).
   - Shows you `git diff --stat` (and a full diff via `gum pager` if
     you want), then `git commit`s the personalization.
   - Optionally creates a new public repo on your account via `gh repo
     create` and pushes.
4. Prints your new bootstrap URL.

Once the fork is up, your friend uses **their** URL going forward:

```bash
curl -fsSL https://raw.githubusercontent.com/<their-user>/<their-repo>/main/bootstrap.sh | bash
```

The Bitwarden item names (`dotforge-ssh-<profile>`) are derived from the
profile string only — no changes needed for them. Your friend will
populate their own Bitwarden vault using the same `add-ssh-key.sh` flow.

### Non-interactive form

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh \
    | bash -s -- fork \
        --gh-user friend-foo \
        --name "Friend Foo" \
        --email friend@example.com \
        --repo dotforge \
        --reset-ssh \
        --create-remote
```

(Flags pass through `cmd_fork` to `personalize-fork.sh`.)

### What the script does NOT touch

- `Brewfile` — kept as-is. Your friend will probably want to run `sync`
  on their machine to overwrite it with what they actually have
  installed, or `customize` to pick a subset.
- `chezmoi/private_dot_zshrc.tmpl` — preserved literally. Friends
  generally have very different shell configs; recommend doing
  `chezmoi re-add ~/.zshrc` on their machine after the first apply.
- `chezmoi/dot_claude/settings.json` — your friend will need to
  delete it (or replace) since it has your `enabledPlugins` list and
  paths under `/Users/romandubovik/`.
- `docs/superpowers/*` — historical design docs left intact for
  reference.

The script prints a "what to clean up next" hint at the end. If you want
a stricter wipe (drop all of Roman's dotfiles, keep just the bootstrap
machinery), do `chezmoi re-add` on the friend's actual machine after
their first apply — it'll bring their real `.zshrc`, `.gitconfig`, etc.
into their fork's source.

### Manual path (if you don't want to use the script)

```bash
gh repo create <you>/<repo-name> --public --clone
cd <repo-name>
# Pull this repo's contents
git remote add upstream https://github.com/roman-dubovik/dotforge.git
git fetch upstream main
git reset --hard upstream/main

# Find/replace by hand
grep -rl 'roman-dubovik/dotforge' . --exclude-dir=.git \
    | xargs sed -i '' "s|roman-dubovik/dotforge|<you>/<repo-name>|g"
grep -rl 'Roman Dubovik' . --exclude-dir=.git \
    | xargs sed -i '' "s|Roman Dubovik|<Your Name>|g"
grep -rl 'booroman@gmail.com' . --exclude-dir=.git \
    | xargs sed -i '' "s|booroman@gmail.com|<your-email>|g"

# Clean up upstream remote
git remote remove upstream

git add -A
git commit -m "chore: personalize fork"
git push
```

---

## CLI globals (npm, pnpm, cargo, go, pip)

The Brewfile only covers things Homebrew can install. CLI tools that come
from a language-specific package manager (npm / pnpm / cargo / go / pip)
or from a curl-installed binary won't reach a fresh Mac through `setup`
alone. `scripts/scan-cli.sh` walks every directory in `$PATH`, classifies
each executable by install source, and (with `--capture`) writes a
`cli-globals.txt` the bootstrap can replay on a new machine.

### Categories

When you run `bootstrap.sh scan-cli` (or `./scripts/scan-cli.sh`) it
classifies every binary in PATH as one of:

| Category | What it is |
|---|---|
| `system` | macOS-bundled (`/usr/bin`, `/bin`, `/sbin`, `/System/*`) |
| `xcode` | Xcode Command Line Tools (`/Library/Developer/CommandLineTools/...`) |
| `brew` | Homebrew formula (`$(brew --prefix)/bin`, `Cellar/*`, `opt/*`) |
| `cask` | Cask CLI shim (`$(brew --prefix)/Caskroom/*`) |
| `npm` | npm global under nvm (`~/.nvm/versions/node/*/bin`) |
| `pnpm` | pnpm global (`~/Library/pnpm` or `$PNPM_HOME`) |
| `cargo` | Rust crate (`~/.cargo/bin`) |
| `go` | Go binary (`$GOBIN` or `$GOPATH/bin` or `~/go/bin`) |
| `pip` | Python user package (`~/.local/bin`) |
| `thirdparty` | `/usr/local/bin` CLIs placed there by a cask's pkg installer (Docker's `kubectl`, Tailscale's `tailscale`) or installed by hand. Skipped on Intel Macs, where `brew --prefix == /usr/local`. The cask itself shows up under `cask`. |
| `uncategorized` | Everything else — typically curl-installed tools (e.g. `~/.maestro/bin`) |

### Capturing globals for replay

```bash
bootstrap.sh scan-cli --capture
```

Requires the repo to be cloned (`bootstrap.sh setup` first on a fresh
Mac). The existing `cli-globals.txt` is copied to `cli-globals.txt.bak`
before being overwritten, so manual edits (e.g. curated `go:` entries)
are recoverable.

Writes `cli-globals.txt` with lines like:

```
npm:typescript
npm:typescript-language-server
npm:ts-node
pnpm:eslint_d
cargo:zoxide
```

Commit + push it. The chezmoi hook
`run_onchange_30-install-cli-globals.sh.tmpl` runs on the next `chezmoi
apply` (or `bootstrap.sh update`) on any machine and replays the file.
The template embeds a sha256 of `cli-globals.txt` so chezmoi re-runs the
hook whenever the file changes. Per-line behavior:

- `npm install -g <pkg>` for each `npm:` line (skipped if `npm` isn't on
  PATH; install nvm first)
- `pnpm add -g <pkg>` for each `pnpm:` line
- `cargo install <crate>` for each `cargo:` line (idempotent: skipped if
  already installed)
- `pip3 install --user <pkg>` for each `pip:` line
- `go:` lines are reported but not auto-installed — Go needs full module
  paths, which the binary name alone doesn't reveal

The hook is idempotent — already-installed packages are skipped quietly.
Failures are logged but don't abort the run.

### What's NOT auto-captured

- **curl-installed binaries** (e.g. `~/.maestro/bin/maestro`,
  `~/.cargo/bin/rustup`'s installer) — these install themselves into
  custom dirs via their own `curl ... | sh`. Listed under
  `# ── Manual install ──` at the bottom of `Brewfile` with their source
  URLs.
- **App-bundled CLIs** (Docker's `kubectl`, Tailscale's `tailscale`) —
  these come with the corresponding cask. Once you `brew install --cask
  --adopt <name>` (suggested by `bootstrap.sh sync`), the cask installer
  will also place the CLI.

### Inspect without capturing

```bash
bootstrap.sh scan-cli --uncategorized   # only the uncategorized list
bootstrap.sh scan-cli --json            # machine-readable
```

---

## Chezmoi hooks (Plan 1.5 additions)

### `run_onchange_25-install-curl-toolchains.sh`

Installs the non-brew toolchains that the managed `.zshrc` depends on. Runs between the Brewfile hook (`20`) and the CLI-globals hook (`30`), so that `nvm` is available before npm globals are replayed.

Installs (each idempotent — skipped if already present):

- **oh-my-zsh** via the official installer with `--unattended --keep-zshrc` to avoid clobbering the managed `~/.zshrc`
- **powerlevel10k** theme (git clone into `$ZSH_CUSTOM/themes/`)
- Three zsh custom plugins: `zsh-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions`
- **nvm** plus the current Node LTS so subsequent `npm i -g …` calls work
- **pnpm**
- **maestro** (mobile UI testing CLI)

Individual installer failures log a warning but do not abort the hook — one broken toolchain cannot block the rest of `chezmoi apply`.

Dry-run preview without touching the network:

```bash
DRY_RUN=1 bash chezmoi/.chezmoiscripts/run_onchange_25-install-curl-toolchains.sh
```

### `run_onchange_60-apply-macos-defaults.sh`

Applies a baseline of ~35 macOS `defaults write` keys across Dock, Finder, Screenshots, Keyboard, Trackpad, UI, and Safari. All writes are user-level domains (no `sudo`). After applying, the hook runs `killall Dock Finder SystemUIServer` so changes are visible immediately.

Dry-run preview:

```bash
DRY_RUN=1 bash chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh
```

To see what your current Mac has versus the baseline, use the companion `scan-macos` subcommand (see below).

### `run_onchange_70-apply-login-autostart.sh`

Two related autostart mechanisms in one hook:

1. **Login Items** — reads `login-items.txt` from the repo root (one absolute app path per line; lines starting with `#` are comments). Each path becomes an entry in System Settings → General → Login Items via osascript. Idempotent: already-present entries are skipped. Missing apps log a warning and are skipped.
2. **Custom LaunchAgents** — for every `.plist` chezmoi placed under `~/Library/LaunchAgents/` (sourced from `chezmoi/private_dot_Library/private_LaunchAgents/` in the repo), the hook runs `launchctl bootout` then `launchctl bootstrap` to reload the agent. Per-user only — no `sudo`, no `/Library/LaunchDaemons/`.

Note: LaunchAgents that a brew cask installs (Docker Desktop, iTerm2, Karabiner, etc.) belong to those apps and rebuild on `brew bundle` — do not version them in this repo.

Dry-run preview:

```bash
DRY_RUN=1 bash chezmoi/.chezmoiscripts/run_onchange_70-apply-login-autostart.sh
```

First run may trigger a macOS Automation permission prompt for System Events. Grant it in System Settings → Privacy & Security → Automation, then re-run the hook.

### `bootstrap.sh scan-macos`

Reads the current `defaults read` value for each baseline key and prints ready-to-paste `defaults write` lines. Use `--diff` to surface only keys where your current state differs from the hook's baseline:

```bash
bootstrap.sh scan-macos          # full snapshot of all 35 keys
bootstrap.sh scan-macos --diff   # only divergent keys, with baseline values for reference
```

The output is meant to be copy-pasted as additional `defaults write` lines into the hook if you discover settings you want to promote to the baseline.

### `bootstrap.sh scan-autostart`

Read-only survey of the current Mac's autostart state. Prints two sections:

- **Login Items** — copy-paste-ready paths for `login-items.txt`. Run this first on your canonical Mac to seed the baseline.
- **LaunchAgents** — a human-readable table of every `~/Library/LaunchAgents/*.plist` with its Label, target binary, and a guess at the source (cask vs custom). Use this to identify which plists are worth versioning into `chezmoi/private_dot_Library/private_LaunchAgents/`.

```bash
bootstrap.sh scan-autostart           # snapshot
bootstrap.sh scan-autostart --diff    # show login items that diverge from login-items.txt
```

---

## Diagnostic — `bootstrap.sh doctor`

Read-only sync check: runs 8 checks against canonical state and reports which areas are in sync or have drifted. Nothing is modified — safe to run at any time, including from cron or CI.

```
dotforge doctor — 2026-05-16T18:23

[OK]   chezmoi state         no pending changes
[WARN] Brewfile              2 missing: htop, lazydocker
[OK]   CLI globals           9/9 npm packages present
[OK]   Curl-toolchains       8/8 installed
[OK]   SSH keys              2 keys present (personal scope)
[WARN] macOS defaults        3 keys diverge from baseline (run scan-macos --diff)
[OK]   Login items           matches baseline; 0 chezmoi-managed LaunchAgents
[OK]   Repo                  up to date with origin/main

Summary: 6 OK, 2 WARN, 0 FAIL
```

**Exit codes:**

- `0` — all checks OK
- `1` — at least one WARN, no FAIL (drift exists but the setup is functional)
- `2` — at least one FAIL (e.g. chezmoi not initialized — fundamentally broken setup)

**Single-check debugging:**

Pass `--check=<name>` to run only one check. Valid names: `chezmoi`, `brewfile`, `cli-globals`, `curl-toolchains`, `ssh-keys`, `macos-defaults`, `login-autostart`, `repo`. Exit code reflects that check alone.

```bash
bootstrap.sh doctor --check=brewfile
bootstrap.sh doctor --check=macos-defaults
```

**Color and pipe-safe output:**

Output is plain text by default so `bootstrap.sh doctor | grep WARN` works. Pass `--color` to enable ANSI colors; the script also auto-detects a TTY and enables color automatically when stdout is a terminal.

---

## `dot` CLI

Unified namespace for dotforge operations, installed at `~/.local/bin/dot` via chezmoi on every `chezmoi apply`.

### Subcommands

| Subcommand | Description |
|---|---|
| `doctor [--check=<name>]` | Run read-only diagnostic checks — identical to `bootstrap.sh doctor` |
| `apply [--dry-run]` | Apply chezmoi dotfiles and show before/after doctor delta; `--dry-run` runs `chezmoi diff` without mutating |
| `snapshot [--no-cli] [--no-autostart] [--no-macos]` | Capture current machine state (CLI globals, login items, macOS defaults) into canonical files and prompt for a git commit — 3 scanners by default |
| `pull` | Sync from origin: `git pull --ff-only`, `chezmoi apply`, then `dot doctor`; strict bail on any error |
| `help` | Show usage and available subcommands |
| `version` | Print repo HEAD short hash and branch name |

### Example: `dot help`

```
dotforge dot — unified CLI for diagnostics and configuration

Usage:
  dot [SUBCOMMAND] [OPTIONS]

Subcommands:
  doctor [--check=<name>]       run read-only diagnostic checks
  apply [OPTIONS]               apply chezmoi dotfiles with before/after doctor delta
  snapshot [OPTIONS]            capture current machine state to canonical files + git commit
  pull [OPTIONS]                sync from origin: git pull --ff-only, chezmoi apply, doctor
  version                        print version and branch
  help, -h, --help              show this help message

Options (doctor):
  --check=<name>                run a single named check
  --color, --no-color           force or disable ANSI colors

Named checks: chezmoi, brewfile, cli-globals, curl-toolchains,
              ssh-keys, macos-defaults, login-autostart, repo

Exit codes:
  0                             all checks passed
  1                             one or more warnings
  2                             one or more failures
```

### Usage

```bash
dot doctor                    # full 8-check diagnostic (= bootstrap.sh doctor)
dot doctor --check=brewfile   # single-check mode
dot version                   # e.g. "dotforge abc1234 on main"
dot help                      # print usage

# Fix drift: apply dotfiles and see what changed
dot apply                     # chezmoi apply + before/after doctor delta (e.g. "1 WARN → 0 WARN")

# Preview what chezmoi would change without mutating
dot apply --dry-run           # runs chezmoi diff, exits without writing anything

# Capture current machine state after installing new tools
dot snapshot                  # scan CLI globals + login items + macOS defaults, then prompt per-file git commit
dot snapshot --no-autostart   # skip login-items scan
dot snapshot --no-macos       # skip macOS defaults scan

# Sync dotfiles from another machine (e.g. pulling changes made on mac-mini)
dot pull                      # git pull --ff-only + chezmoi apply + dot doctor; bails on any error
```

The `dot` binary is placed at `chezmoi/dot_local/bin/executable_dot` in the repo and lands at `~/.local/bin/dot` after `chezmoi apply`. Ensure `~/.local/bin` is in your `$PATH` (the managed `.zshrc` includes it).

---

## Profiles

`profile` is a single string (`personal` or `work`) that gates conditional
blocks in templates:

- **`dot_gitconfig.tmpl`** — selects email
  (`booroman@gmail.com` for personal, `roman@work-domain.example` placeholder
  for work).
- **`private_dot_zshrc.tmpl`** — wraps the personal-only PATH exports
  (PostgreSQL@16, libpq, mysql-client, ngrok completion).
- **`private_dot_ssh/config.tmpl`** — only the personal block ships a
  `Host github` entry; the work block is a placeholder for future hosts.
- **`run_onchange_50-pull-ssh-keys.sh.tmpl`** — chooses the array of SSH key
  basenames to restore from Bitwarden (5 for personal, 1 placeholder for
  work).

Switching profile on an existing machine: edit
`~/.config/chezmoi/chezmoi.toml` and change `profile = "..."`, then
`chezmoi apply`.

---

## Daily operations

After bootstrap, the repo lives at
`~/.local/share/chezmoi` (and is also cloned to
`~/Documents/Projects/dotforge` for direct git work, by convention).

### Update from upstream

```bash
chezmoi update          # git pull + apply in one command
chezmoi update --dry-run -v   # preview only
```

### Apply changes you've made to the repo

```bash
chezmoi diff            # show what apply would change
chezmoi apply -v        # apply
chezmoi apply --include=files       # only dotfiles, skip scripts
chezmoi apply --include=scripts     # only scripts (re-run hooks)
```

### Edit a managed file

```bash
chezmoi edit ~/.zshrc   # opens the source template ($EDITOR)
chezmoi apply           # apply the change
```

`chezmoi edit` knows the mapping `~/.zshrc → private_dot_zshrc.tmpl` and
opens the template in the source dir.

### Pull new local edits back into the repo

If you edited `~/.zshrc` directly (without going through `chezmoi edit`)
and want to bring those changes into the source template:

```bash
chezmoi re-add ~/.zshrc
git -C ~/.local/share/chezmoi diff   # review
git -C ~/.local/share/chezmoi commit -am "tweak zshrc"
git -C ~/.local/share/chezmoi push
```

`re-add` does **not** preserve template directives. If the file is `.tmpl`
and the change should be conditional on a profile, you must restore the
`{{ if eq .profile ... }}` blocks by hand.

### Re-run only the SSH-keys hook

Useful if you added a new key to Bitwarden and want it pulled down:

```bash
export BW_SESSION="$(bw unlock --raw)"
chezmoi execute-template < ~/.local/share/chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl | bash
bw lock && unset BW_SESSION
```

This bypasses the normal once-per-change tracking, so you can run it as
many times as you want.

### Re-run brew bundle

```bash
cd ~/.local/share/chezmoi/.. && brew bundle install --file=Brewfile
# or, equivalently:
chezmoi apply --include=scripts -v
```

The `--include=scripts` form will also run the SSH-keys and install-bw
hooks; if you want only the brewfile, invoke `brew bundle` directly.

### Validate without installing

```bash
brew bundle check --verbose --file=Brewfile
```

Read-only check that every formula and cask name in the Brewfile resolves
and reports what's missing.

---

## Adding or rotating SSH keys

SSH keys are stored as Bitwarden **attachments** in two-tier items, and the
chezmoi hook reads the list of attachments dynamically — adding or rotating
a key never requires a code change to the hook.

### Two-tier item naming

| Bitwarden item | Scope | Use this for |
|---|---|---|
| `dotforge-ssh-<profile>` | shared across all machines using `profile` | the GitHub key you want on every personal Mac |
| `dotforge-ssh-<profile>-<machine_name>` | only on this machine | a default `id_ed25519` whose content differs per machine, or a one-off deploy key |

The hook enumerates attachments in both items and downloads them. On
basename collision (the same `id_X` appears in both), **machine-level wins**
— useful when you want a profile-shared default but override it on one Mac.

### Add keys

The helper script supports three modes:

```bash
# A) BULK SCAN — finds local ~/.ssh/id_* keys not yet in Bitwarden,
#    presents a multi-select, then uploads the chosen ones with one
#    scope choice for the batch.
~/.local/share/chezmoi/scripts/add-ssh-key.sh

# B) SINGLE — upload one specific key
~/.local/share/chezmoi/scripts/add-ssh-key.sh id_ed25519_work_jenkins

# C) INVENTORY — read-only listing of what's where (no upload prompts)
~/.local/share/chezmoi/scripts/add-ssh-key.sh --list
```

**Scope choice (asked once per run, applies to all selected keys):**

- `profile` — uploads to `dotforge-ssh-<profile>`. Visible to every
  machine using that profile.
- `machine` — uploads to `dotforge-ssh-<profile>-<machine_name>`. This
  machine only.

**Non-interactive form** (skips the gum picker):

```bash
add-ssh-key.sh id_ed25519_x --scope profile --non-interactive
add-ssh-key.sh --scope machine --non-interactive   # bulk mode + scope
```

**Duplicate handling**: if a key with the same basename is already an
attachment in the target item, you'll be asked before appending a
duplicate (or pass `--force`). Bitwarden tolerates duplicate filenames
but `bw_get_attachment` would pick one arbitrarily — almost always you
want to delete the old via the GUI first, then re-upload.

You can also start the helper from the bootstrap menu — pick `add-key`.
The bootstrap unlocks Bitwarden for you if needed.

**Sample inventory output (`--list`):**

```
── Profile-shared (dotforge-ssh-personal) ──
  id_ed25519_github_booroman [also on disk]
  id_ed25519                  [also on disk] [overridden by machine]
  id_rsa                      [also on disk]
  id_rsa_pureboard            [also on disk]

── Machine-only (dotforge-ssh-personal-mac-mini) ──
  id_ed25519                  [also on disk] [overrides profile]

── Local in ~/.ssh, not in Bitwarden ──
  id_ed25519_new_key
```

The `[overrides profile]` / `[overridden by machine]` markers make the
collision-resolution rule (machine wins) visible at a glance.

### Verify on this machine

```bash
chezmoi apply --include=scripts -v
```

The hook is a no-op when keys are already on disk; it only fetches what's
missing or zero-byte. Or trigger only the SSH-keys hook directly:

```bash
chezmoi execute-template < ~/.local/share/chezmoi/chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl | bash
```

### Verify on other machines

The next `chezmoi update` (or `bootstrap.sh update` from the menu) on any
other machine of the same profile will pick up profile-scoped keys
automatically. Machine-scoped keys are invisible to other machines by
design.

### Rotate a key

1. Generate the new pair, replace `~/.ssh/id_*` and `~/.ssh/id_*.pub`
   locally.
2. **Delete the old attachments** from the Bitwarden item via the GUI.
   (Bitwarden does not auto-replace; without deleting, you'll have two
   attachments with the same filename — `bw_get_attachment` picks one
   arbitrarily.)
3. Re-upload via `add-ssh-key.sh <basename>`.

### Bulk-load existing keys (legacy seeding)

`scripts/seed-bitwarden-ssh-keys.sh personal` was the original
one-shot helper that uploads a hardcoded list of basenames at profile
scope. It still works, but `add-ssh-key.sh` is the recommended path for
new keys.

### Migrating from the old single-tier hook

If you set up before the two-tier change, your `dotforge-ssh-<profile>`
item already exists with all keys at profile scope. No migration is
needed — the new dynamic hook reads the same item and finds the same
keys. To move a specific key down to machine scope:

1. Delete its private and `.pub` attachments from `dotforge-ssh-<profile>`
   in the Bitwarden GUI.
2. `add-ssh-key.sh <basename> --scope machine`

---

## Editing dotfiles

The mapping between source filename and target path follows chezmoi's
naming conventions (see [next section](#chezmoi-naming-conventions)).
Some examples:

| Edit this in repo | Affects this on disk |
|---|---|
| `chezmoi/private_dot_zshrc.tmpl` | `~/.zshrc` (mode 0600) |
| `chezmoi/dot_gitconfig.tmpl` | `~/.gitconfig` |
| `chezmoi/private_dot_ssh/config.tmpl` | `~/.ssh/config` (parent dir 0700) |
| `chezmoi/dot_claude/settings.json` | `~/.claude/settings.json` |
| `chezmoi/dot_claude/private_plugins/.gitkeep` | `~/.claude/plugins/` (0700) |
| `Brewfile` (repo root) | runs `brew bundle install` via hook |

Recommended workflow:

```bash
chezmoi edit ~/.zshrc          # edits the source template
chezmoi diff                   # preview the change against ~/.zshrc
chezmoi apply -v               # apply
git -C ~/.local/share/chezmoi commit -am "zshrc: add foo alias"
git -C ~/.local/share/chezmoi push
```

---

## Managing Bitwarden secrets

The repo uses Bitwarden for one thing only (in Plan 1): SSH key storage.
Conventions:

- **Item name** — `dotforge-ssh-<profile>` (e.g., `dotforge-ssh-personal`).
- **Item type** — Secure Note (type 2). Login fields are stubbed but
  unused.
- **Attachments** — one private and one `.pub` per key basename. Attachment
  filename matches the basename exactly (`id_ed25519_github_booroman`,
  `id_ed25519_github_booroman.pub`, etc).
- **Custom fields (optional)** — `profile`, `created_at`, `fingerprint`,
  `algorithm`. The hooks do not depend on these; they're for the human.

The chezmoi hook reads attachments via `bw_get_attachment` (in
`lib/secrets.sh`) which has three fallback strategies for compatibility
across `bw` versions and mocking.

---

## Repository layout

```
.
├── .chezmoiroot                 # tells chezmoi the source dir is `chezmoi/`
├── Brewfile                     # all brew formulas, casks, taps, mas, vscode
├── README.md
├── LICENSE                      # MIT
├── bootstrap.sh                 # the one-command-bootstrap entry
├── scripts/
│   ├── customize-brewfile.sh    # interactive Brewfile customizer (writes Brewfile.local)
│   ├── sync-brewfile.sh         # diff + promote machine extras back to Brewfile
│   ├── scan-cli.sh              # classify every PATH binary; capture CLI globals
│   ├── add-ssh-key.sh           # upload an SSH key to Bitwarden (profile or machine scope)
│   ├── personalize-fork.sh      # rewrite hardcoded user strings + push to your own gh
│   └── seed-bitwarden-ssh-keys.sh   # legacy one-shot bulk SSH-key seeder
├── lib/
│   ├── log.sh                   # info/ok/warn/error/step/section helpers
│   └── secrets.sh               # bw wrappers (is_unlocked / get_attachment)
├── tests/
│   └── lib/
│       ├── log.bats             # 3 tests
│       └── secrets.bats         # 2 tests (with bw mock)
├── docs/
│   ├── usage.md                 # this file
│   └── superpowers/             # design spec + plan
│       ├── plans/
│       └── specs/
└── chezmoi/                     # chezmoi source dir (per .chezmoiroot)
    ├── .chezmoi.toml.tmpl       # generates ~/.config/chezmoi/chezmoi.toml
    ├── .chezmoiignore           # paths under ~/.claude excluded from management
    ├── private_dot_zshrc.tmpl   # ~/.zshrc, mode 0600
    ├── dot_gitconfig.tmpl       # ~/.gitconfig
    ├── private_dot_ssh/
    │   └── config.tmpl          # ~/.ssh/config (parent ~/.ssh/ at 0700)
    ├── dot_claude/
    │   ├── settings.json        # ~/.claude/settings.json
    │   ├── CLAUDE.md            # tracked global Claude instructions
    │   ├── skills/              # tracked skills (graphify, session-handoff)
    │   └── private_plugins/     # ~/.claude/plugins/, mode 0700
    └── .chezmoiscripts/
        ├── run_once_before_10-install-bw.sh
        ├── run_onchange_20-apply-brewfile.sh.tmpl
        ├── run_onchange_30-install-cli-globals.sh.tmpl  # replays cli-globals.txt
        └── run_onchange_50-pull-ssh-keys.sh.tmpl
```

`chezmoi/.chezmoiignore` lists `~/.claude/` subdirectories whose contents
are session/state noise (history.jsonl, todos, projects, plans, …) and
must stay machine-local. Adding a new managed path under `dot_claude/`
generally requires no change to `.chezmoiignore`; adding a new noisy
sibling does — see the file's header for the current exclusion list.

---

## chezmoi naming conventions

chezmoi uses filename prefixes/suffixes to control behavior. The ones used
in this repo:

| Prefix | Effect |
|---|---|
| `dot_<name>` | target is `~/.<name>` (the leading dot is encoded so files don't appear hidden in the source) |
| `private_<name>` | target permissions are 0700 (dir) / 0600 (file) |
| `private_dot_<name>` | combines both (e.g., `private_dot_zshrc.tmpl` → `~/.zshrc` at 0600) |
| `<name>.tmpl` | rendered as a Go template (data from `[data]` in `chezmoi.toml`) |

Special directories:

- **`.chezmoiroot`** — single-line file at repo root naming the subdir to
  treat as the source. We use `chezmoi`.
- **`.chezmoi.toml.tmpl`** — at the source root, generates
  `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`. This is where
  `promptStringOnce` lives.
- **`.chezmoiscripts/`** — script files that are **executed** rather than
  copied to `$HOME`. Filename order:
  - `run_once_*` — runs exactly once per machine.
  - `run_onchange_*` — re-runs whenever the file's hash changes.
  - The numeric prefix sorts execution order: `10-`, `20-`, `50-`, etc.
  - Suffix `before` (in `run_once_before_*`) means before the rest of
    `apply`; default is after.

Documentation: <https://www.chezmoi.io/reference/source-state-attributes/>.

---

## Troubleshooting

### Bootstrap stops on "waiting for Xcode CLT"

The Xcode installer dialog is up but you haven't accepted the EULA. Click
*Install* in the GUI dialog and wait. Bootstrap polls `xcode-select -p`
every 5 seconds until the install completes.

### `gum input` produces no prompt

You ran `bootstrap.sh` via a non-interactive shell (e.g., piped into bash
without a TTY). gum requires a controlling terminal. Re-run from an
interactive terminal session — the canonical command does this:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

If `curl ... | bash` doesn't give a TTY in your environment, save the
script first and run it directly:

```bash
curl -fsSLo /tmp/bootstrap.sh https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh
bash /tmp/bootstrap.sh
```

### `chezmoi apply` says `stat .../.local/share/chezmoi: no such file or directory`

Your `~/.config/chezmoi/chezmoi.toml` was generated without `sourceDir`,
and the default location is empty. Two fixes:

- (a) Add `sourceDir = "/path/to/repo/chezmoi"` to
  `~/.config/chezmoi/chezmoi.toml` (above the `[data]` table).
- (b) Run `chezmoi init roman-dubovik/dotforge --apply` to clone fresh into
  `~/.local/share/chezmoi`.

### `bw create item` returns "Cannot read properties of null (reading 'uris')"

Known issue in `bw 2026.4.x`. Use the seeding helper which sets
`.type = 2` (Secure Note) and stubs `.login = {uris: [], …}`:

```bash
./scripts/seed-bitwarden-ssh-keys.sh personal
```

If you must call `bw create item` by hand, add the same stubs.

### SSH-keys hook says "Failed to fetch private key"

Most common reasons:

- Bitwarden is locked (`bw status` shows `"locked"`). The hook logs a
  warning and exits 0 in this case. Unlock and re-run.
- An attachment is missing on the Bitwarden item — verify with
  `bw list items --search dotforge-ssh-personal`. Re-seed if needed.
- Network failure mid-download — the hook's `ERR` trap removes the
  partially written file from disk. Re-run safely.

### `brew bundle install` fails on a manually installed app

If you have an app installed via drag-and-drop in `/Applications` and the
Brewfile lists the matching cask, `brew bundle install` will try to install
the cask and may abort because the app already exists. Fix by adopting:

```bash
brew install --cask --adopt <cask-name>
```

This registers the existing app with brew without reinstalling. Repeat for
any conflicting cask.

### `chezmoi diff` shows mode changes for `.zshrc` (100600 → 100644)

Means your local `~/.zshrc` is at the user's odd mode and the template is
the default. We use `private_dot_zshrc.tmpl` (private prefix) to enforce
mode 0600 on disk, matching the canonical state. If your file came from
some other source at 0644 and you want to keep it that way, rename to
`dot_zshrc.tmpl` (drop the `private_` prefix).

### "config file template has changed, run chezmoi init to regenerate"

chezmoi noticed `.chezmoi.toml.tmpl` is newer than your generated config.
Re-run `chezmoi init` (no args needed if you have `sourceDir` set) to
regenerate `~/.config/chezmoi/chezmoi.toml`.

---

## What is not yet covered

These are intentionally left for **Plan 2e / Plan 3** (`docs/superpowers/plans/`):

- **Programmatic feature toggle (`dot apply --enable=X --disable=Y`)** — slice 2e. Currently use `bootstrap.sh customize` or edit `~/.config/chezmoi/chezmoi.toml` manually and re-apply.
- **`local_llm` feature flag** — deferred to slice 2e when ollama integration lands in the Brewfile.
- **Multi-machine sync** — Plan 3 territory: keeping personal-mac-mini
  and personal-mbp aligned through the repo.
- **Non-brew toolchain installers** — automating `oh-my-zsh`, `nvm`,
  `pnpm`, `powerlevel10k`, `maestro` (currently listed as a comment block
  at the bottom of `Brewfile` for manual install).
- **Mac App Store automation** — the Brewfile lists `mas` entries, but
  `mas install` requires you to be signed in to the App Store first. Add
  a hook for this in Plan 2.
- **App-specific config restore** — Raycast, VS Code/Cursor, JetBrains, iTerm/Warp profiles, Hammerspoon, Rectangle/BetterDisplay are not yet auto-restored.

If you want to add any of these now without waiting, they slot naturally
into the existing structure — see the plan docs for sketches.
