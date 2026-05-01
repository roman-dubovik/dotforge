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
7. [Profiles](#profiles)
8. [Daily operations](#daily-operations)
9. [Adding or rotating SSH keys](#adding-or-rotating-ssh-keys)
10. [Editing dotfiles](#editing-dotfiles)
11. [Managing Bitwarden secrets](#managing-bitwarden-secrets)
12. [Repository layout](#repository-layout)
13. [chezmoi naming conventions](#chezmoi-naming-conventions)
14. [Troubleshooting](#troubleshooting)
15. [What is not yet covered](#what-is-not-yet-covered)

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
    sync      — Promote local extras into the canonical Brewfile
    customize — Re-pick which Brewfile sections to install
    add-key   — Upload a new SSH key to Bitwarden (profile or machine scope)
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
- Archetype selection (dev-machine / media / ops-server) and feature flags —
  postponed to Plan 2. The Brewfile customizer (see below) covers the
  90% case via section-level toggling without restructuring the repo.

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

### Add a new key

```bash
# 1) Generate or copy the key locally
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_work_jenkins -C "work-jenkins"

# 2) Upload to Bitwarden via the helper
export BW_SESSION="$(bw unlock --raw)"
~/.local/share/chezmoi/scripts/add-ssh-key.sh id_ed25519_work_jenkins
# → asks: profile (shared) vs machine (this Mac only)
# → auto-creates the Bitwarden item if it doesn't exist
```

Or pick a key interactively if you don't pass the basename:

```bash
~/.local/share/chezmoi/scripts/add-ssh-key.sh
# → lists all ~/.ssh/id_* keys, you pick one
# → asks for scope
```

Non-interactive form (e.g., for a script):

```bash
add-ssh-key.sh id_ed25519_work_jenkins --scope profile --non-interactive
```

You can also start the helper from the bootstrap menu — pick `add-key`.
The bootstrap unlocks Bitwarden for you if needed.

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
│   ├── add-ssh-key.sh           # upload an SSH key to Bitwarden (profile or machine scope)
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
    ├── private_dot_zshrc.tmpl   # ~/.zshrc, mode 0600
    ├── dot_gitconfig.tmpl       # ~/.gitconfig
    ├── private_dot_ssh/
    │   └── config.tmpl          # ~/.ssh/config (parent ~/.ssh/ at 0700)
    ├── dot_claude/
    │   ├── settings.json        # ~/.claude/settings.json
    │   └── private_plugins/     # ~/.claude/plugins/, mode 0700
    └── .chezmoiscripts/
        ├── run_once_before_10-install-bw.sh
        ├── run_onchange_20-apply-brewfile.sh.tmpl
        └── run_onchange_50-pull-ssh-keys.sh.tmpl
```

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

These are intentionally left for **Plan 2** (`docs/superpowers/plans/`):

- **First-class archetypes / feature flags persisted in chezmoi data** —
  the Brewfile customizer above covers the "pick a subset" use case
  without restructuring the repo, but the chosen archetype lives in a
  one-off `Brewfile.local` rather than `~/.config/chezmoi/chezmoi.toml`,
  so re-running `chezmoi init` on a new machine doesn't carry the
  archetype forward. Plan 2 will promote `archetype` and a `features`
  list into `[data]`, where templates can reference them.
- **`dot` CLI** — convenience wrapper providing `dot apply`, `dot doctor`,
  `dot snapshot`, `dot pull`, etc.
- **Multi-machine sync** — Plan 3 territory: keeping personal-mac-mini
  and personal-mbp aligned through the repo.
- **Non-brew toolchain installers** — automating `oh-my-zsh`, `nvm`,
  `pnpm`, `powerlevel10k`, `maestro` (currently listed as a comment block
  at the bottom of `Brewfile` for manual install).
- **Mac App Store automation** — the Brewfile lists `mas` entries, but
  `mas install` requires you to be signed in to the App Store first. Add
  a hook for this in Plan 2.
- **macOS defaults** — system settings like keyboard repeat, Finder
  hidden-file display, Dock auto-hide, etc. (`defaults write …`).

If you want to add any of these now without waiting, they slot naturally
into the existing structure — see the plan docs for sketches.
