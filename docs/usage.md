# dotforge — Usage Guide

End-to-end usage and operations reference for the
[roman-dubovik/dotforge](https://github.com/roman-dubovik/dotforge) bootstrap.

## Contents

1. [Quick start (fresh Mac)](#quick-start-fresh-mac)
2. [Prerequisites](#prerequisites)
3. [What the bootstrap does](#what-the-bootstrap-does)
4. [Interactivity](#interactivity)
5. [Profiles](#profiles)
6. [Daily operations](#daily-operations)
7. [Adding or rotating SSH keys](#adding-or-rotating-ssh-keys)
8. [Editing dotfiles](#editing-dotfiles)
9. [Managing Bitwarden secrets](#managing-bitwarden-secrets)
10. [Repository layout](#repository-layout)
11. [chezmoi naming conventions](#chezmoi-naming-conventions)
12. [Troubleshooting](#troubleshooting)
13. [What is not yet covered](#what-is-not-yet-covered)

---

## Quick start (fresh Mac)

On a clean macOS install, open Terminal and run a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

Total time on a clean machine: ~15–20 minutes (most of it is Homebrew + cask
downloads). You will be prompted three times:

1. **Xcode Command Line Tools installer** — the macOS GUI dialog that appears;
   click *Install* and accept the EULA. Bootstrap waits until installation
   completes.
2. **Machine name** (gum) — short, human-friendly identifier. Default is the
   machine's `LocalHostName`. Used in templates only; nothing critical depends
   on it yet.
3. **Profile** (gum) — `personal` or `work`. Determines git email, SSH key
   names, and any profile-conditional dotfile blocks.
4. **Bitwarden master password** — typed into `bw login` / `bw unlock` (and 2FA
   if your account uses it). Bootstrap unlocks the vault, runs SSH-key
   restoration, and locks the vault again on exit.

After completion, **restart your shell** (open a new tab in iTerm/Terminal) so
the new `~/.zshrc` is sourced.

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
7. **chezmoi init + apply** — clones `roman-dubovik/dotforge` to
   `~/.local/share/chezmoi`, reads `.chezmoiroot` to find the `chezmoi/`
   subdirectory as the source, generates `~/.config/chezmoi/chezmoi.toml`
   from `.chezmoi.toml.tmpl` (using the prompt values), then applies all
   managed files plus runs the script hooks:
   - `run_once_before_10-install-bw.sh` — guarantees `bitwarden-cli` and `yq`
     even if Brew is in an odd state (idempotent).
   - `run_onchange_20-apply-brewfile.sh.tmpl` — runs `brew bundle install`
     against the repo's `Brewfile` (re-runs when the file content or profile
     changes).
   - `run_onchange_50-pull-ssh-keys.sh.tmpl` — restores SSH keys from
     Bitwarden into `~/.ssh/`.
8. **Done message** — bootstrap reminds you to restart your shell.

---

## Interactivity

Interactivity is wired at two layers and intentionally minimal in Plan 1:

| Layer | Tool | Where | What it asks |
|---|---|---|---|
| Bootstrap | `gum input` | `bootstrap.sh` | Machine name (default = `LocalHostName`) |
| Bootstrap | `gum choose` | `bootstrap.sh` | Profile: `personal` or `work` |
| Bootstrap | `bw login` / `bw unlock` | `bootstrap.sh` | Bitwarden email + master password (+ 2FA) |
| Xcode CLT | macOS native dialog | OS-managed | License acceptance |
| chezmoi | `promptStringOnce` | `.chezmoi.toml.tmpl` | Same `machine_name`, only fires if `bootstrap.sh` skipped |
| chezmoi | `promptChoiceOnce` | `.chezmoi.toml.tmpl` | Same `profile`, only fires if `bootstrap.sh` skipped |

Things deliberately **not interactive** (per Plan 1 scope):

- The Brewfile is applied without confirmation. Casks and formulas listed in
  `Brewfile` install directly on first apply.
- SSH-key restoration silently skips if Bitwarden is locked (it logs a warning
  and exits 0, so the rest of `chezmoi apply` continues). On the next run
  with a valid `BW_SESSION`, the keys download.
- Archetype selection (dev-machine / media / ops-server) and feature flags —
  postponed to Plan 2.

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

The design stores all keys for a profile as **attachments** on a single
Bitwarden item named `dotforge-ssh-<profile>`. The chezmoi hook pulls a
hard-coded list of basenames per profile.

### Add a new key

1. Generate or copy the key into `~/.ssh/id_ed25519_<short_name>` and the
   matching `.pub`. Set perms `0600` / `0644`.

2. Append the basename to the per-profile array in
   `chezmoi/.chezmoiscripts/run_onchange_50-pull-ssh-keys.sh.tmpl`:

   ```bash
   {{ if eq .profile "personal" -}}
   KEY_BASENAMES=(
       id_ed25519_github_booroman
       id_ed25519
       id_ed25519_ident_tg_bot
       id_rsa
       id_rsa_pureboard
       id_ed25519_NEW_KEY        # <-- add here
   )
   ```

3. Mirror the same list in `scripts/seed-bitwarden-ssh-keys.sh` so re-seeding
   stays in sync.

4. Upload the new pair to Bitwarden:

   ```bash
   export BW_SESSION="$(bw unlock --raw)"
   bw create attachment --itemid <ITEM_ID> --file ~/.ssh/id_ed25519_NEW_KEY
   bw create attachment --itemid <ITEM_ID> --file ~/.ssh/id_ed25519_NEW_KEY.pub
   bw lock && unset BW_SESSION
   ```

   Get `<ITEM_ID>` with `bw list items --search dotforge-ssh-personal | jq -r '.[0].id'`.

5. Commit, push.

### Rotate a key

1. Generate the new pair, replace `~/.ssh/id_*` and `~/.ssh/id_*.pub` locally.
2. Delete the **old** attachments from the Bitwarden item via the GUI.
3. Re-run the seeding script (it will only upload basenames declared in the
   profile list, but will append next to existing — so delete first):

   ```bash
   ./scripts/seed-bitwarden-ssh-keys.sh personal
   ```

### Re-seed everything from scratch

If you want to start over — fresh Bitwarden item, fresh attachments — delete
the existing `dotforge-ssh-personal` item via the Bitwarden GUI, then run:

```bash
export BW_SESSION="$(bw unlock --raw)"
./scripts/seed-bitwarden-ssh-keys.sh personal
```

The script creates a new Secure Note item and uploads all 10 attachments
(5 pairs).

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
│   └── seed-bitwarden-ssh-keys.sh   # one-shot helper to populate Bitwarden
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

- **Archetypes** — switch a machine between roles like `dev-machine`,
  `media-server`, `ops-bastion`, with role-specific Brewfiles.
- **Feature flags** — opt in / out of bundles like `mobile-dev`,
  `database-tools`, `ai-tools`.
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
