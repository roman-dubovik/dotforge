# roman-dubovik/dotforge

Personal Mac bootstrap. One command on a fresh Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
```

## What it does

1. Installs Xcode Command Line Tools
2. Installs Homebrew
3. Installs CLI tools, GUI apps from `Brewfile`
4. Sets up dotfiles (`.zshrc`, `.gitconfig`, `~/.ssh/config`) via [chezmoi](https://chezmoi.io)
5. Restores SSH keys from Bitwarden (item: `dotforge-ssh-<profile>`)
6. Configures Claude Code (`~/.claude/`)

Takes ~15-20 minutes on a clean machine.

## Profiles

- `personal` — your own Macs
- `work` — corporate Macs (uses different SSH keys, git email)

## Bitwarden secrets

The bootstrap reads SSH keys from Bitwarden items named:

- `dotforge-ssh-personal` — attachments: `id_ed25519_personal` + `.pub`
- `dotforge-ssh-work` — same for work

Each item has custom fields: `profile`, `created_at`, `fingerprint`, `algorithm`.

## What's NOT here (yet)

- Archetypes (Plan 2): switch between dev-machine/media/ops-server roles
- `dot` CLI (Plan 2): apply/doctor/snapshot/pull commands
- Multi-machine sync (Plan 3)

## Contributing

This is a personal repo. Feel free to fork.
