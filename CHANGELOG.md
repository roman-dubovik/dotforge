# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Public launch: README rewrite as landing document
- GitHub Pages landing site (`docs/index.html` + CSS + JS)
- Curl-installer (`docs/install.sh`) — self-contained for fresh Mac
- `ROADMAP.md` — shipped, next, and deferred features
- This `CHANGELOG.md`
- `dot setup` subcommand — alias for `bootstrap.sh setup`

## [Slice 2d] - 2026-05-17

### Added
- 6 feature flags in `chezmoi.toml.tmpl`: `docker_desktop`, `ai_assistants`, `vpn_suite`, `office_suite`, `media_tools`, `design_tools`
- `scan-macos --capture` mode to snapshot macOS defaults into `chezmoi/dot_config/dotforge/macos-defaults.txt`
- bats test suite for bootstrap and CLI commands
- Documentation for feature flags in launch prompts

### Changed
- Enhanced macOS baseline defaults scanning with capture output
- Refined interactive prompt messaging for Slice 2c (dot apply/snapshot/pull) and Slice 2d (feature flags)

### Fixed
- Brewfile archetype prompt: add "full" default for clarity
- Explicit error message when chezmoi or repo is missing
- Pass `--non-interactive` to hook customize-brewfile call

## [Slice 2c] - 2026-05-16

### Added
- `dot apply` — chezmoi apply + before/after `dot doctor` delta, with `--dry-run` support
- `dot snapshot` — run scanners (cli, login items, macOS defaults) and auto-commit
- `dot pull` — fetch (ff-only) + apply + strict doctor checks

### Changed
- Enhanced dot CLI as primary user-facing interface for sync operations
- Improved error handling in scanner chain

### Fixed
- Various sync-brewfile reliability improvements
- Scanner integration for consistent state capture

## [Slice 2b] - 2026-05-09

### Added
- Persistent Brewfile archetypes: `full`, `minimal-dev`, `cli-server`, `custom`
- Archetype selection prompt during bootstrap
- Auto-regenerate hook for archetype-based Brewfile sections
- Interactive Brewfile customizer with section-level toggles

### Changed
- Brewfile now generated from archetypes + feature flags instead of monolithic file

### Fixed
- Atomic write to Brewfile.local to prevent partial writes on failure
- Correct classify order for Intel/Apple Silicon Macs
- Tap-to-click default disabled in macOS baseline

## [Slice 2a] - 2026-05-07

### Added
- `dot` CLI namespace (chezmoi-managed shim at `~/.local/bin/dot`)
- `dot doctor` — read-only sync orchestrator with 8 checks
- `dot help` and `dot version` commands
- CLI help text integrated into shim

### Changed
- Brewfile sync moved to hook-based trigger on profile/Brewfile change
- Scanner integration foundation for multi-check coordination

### Fixed
- Error handling for tool unavailability
- REPO_BRANCH propagation via DOTFORGE_BRANCH env var

## [Slice 1] - 2026-05-06

### Added
- `bootstrap.sh doctor` subcommand — read-only diagnostic with 8 sync checks
- Doctor checks: Git status, Brewfile sync, macOS defaults, login items, SSH keys, chezmoi status, dot CLI location, dot doctor pass/fail

### Changed
- Bootstrap menu structure to support subcommand pattern

## [Plan 1.5] - 2026-04-15

### Added
- Curl-based toolchain installer hook: oh-my-zsh, Powerlevel10k, nvm, pnpm, maestro
- Sensible macOS defaults baseline (tap-to-click disabled, etc.)
- macOS defaults scanner (`scan-macos-defaults.sh`)
- Login items scanner + auto-apply via osascript

### Changed
- Enhanced chezmoi hooks for interactive setup flow

### Fixed
- Bash 3.2 compatibility across all scripts
- nvm and defaults write error logging

## [Plan 1] - 2026-04-01

### Added
- Foundation bootstrap: Xcode CLT, brew, Brewfile
- chezmoi dotfiles with machine_name and profile prompts
- SSH key management via Bitwarden (Secure Note items)
- Git config (profile-aware email, global ignore)
- .zshrc with profile-conditional blocks
- Claude config import (settings.json, CLAUDE.md, subdirectories)
- `fork` subcommand — personalize repo under different GitHub account
- `add-ssh-key` subcommand — bulk scan and list SSH keys
- `browse` subcommand — interactive walkthrough
- Interactive Brewfile customizer (basic section toggles)
- CLI globals scanner (`scan-cli.sh`) with PATH classifier

### Changed
- Full conversation-driven bootstrap flow with gum prompts

### Fixed
- .chezmoiroot configuration for subdirectory source

## [Initial Commit] - 2026-03-20

Initial repo skeleton with design spec imports.
