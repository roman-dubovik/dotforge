# Slice 2d launch prompt: Feature flags

Status: BLOCKED on slice 2c
Date created: 2026-05-16
Predecessors: Plan 1, 1.5, 2 slices 1+2a+2b (shipped), slice 2c (pending)

## How to use this file

After slice 2c ships:

```
/team-lead docs/superpowers/specs/2026-05-16-slice-2d-feature-flags-prompt.md
```

The team-lead skill will read this prompt, run Phase 0 (almost certainly needs `superpowers:brainstorming` because design decisions are intentionally open), then proceed through normal flow.

## Why blocked on 2c

Feature flags meaningfully integrate with `dot apply` — toggle changes data → re-apply applies the new state. Without 2c (where `dot apply` exists), feature flags would be just data without an action verb. Build 2c first, then 2d as a thin layer on top.

## Context

Roadmap entry: "Feature flags (toggle docker-desktop / jetbrains / local-llm) declared inside archetypes."

The intent: archetypes (`full` / `minimal-dev` / `cli-server` / `custom`) are coarse — they pick whole Brewfile sections. Feature flags are fine-grained — toggle a single package or behavior on/off, orthogonal to archetype.

Example user pain that flags solve:
- Archetype = `minimal-dev` (no media, no office), but I want docker-desktop on this machine → today: switch to `custom` and edit Brewfile.local manually
- Default archetype installs JetBrains, but on the work Mac I want VS Code only → today: same manual edit
- I want local-llm (ollama + models) on one machine but not another → today: separate Brewfile.local per machine

With flags:
```toml
[data]
brewfile_archetype = "minimal-dev"

[data.features]
docker_desktop = true
jetbrains = false
local_llm = true
```

Brewfile templating picks up features and conditionally includes packages. Or customize-brewfile.sh respects flag overrides on top of archetype.

## Design decisions still open (brainstorm these in Phase 0)

1. **Storage shape**: `[data.features.X = bool]` map vs flat `[data] feature_docker = true`? Map is cleaner but requires `index .features "docker_desktop"` template syntax (verbose). Flat keys are simpler templating but pollute root namespace.

2. **Discovery — what features exist?** Options:
   - Hardcoded list in `chezmoi.toml.tmpl` (small, controlled set: ~5-10 toggles)
   - Auto-discover from Brewfile section markers (e.g. lines starting with `# feature:docker-desktop`)
   - Separate `features.toml` manifest file listing all known toggles with descriptions

3. **Brewfile integration mechanism**:
   - **Option A — Templated Brewfile**: `Brewfile.tmpl` containing `{{ if .features.docker_desktop }}cask "docker"{{ end }}` blocks. chezmoi expands at apply time. Brewfile becomes chezmoi-managed (currently it's a plain file in repo root).
   - **Option B — Post-customize filter**: `customize-brewfile.sh` accepts `--enable=docker-desktop --disable=jetbrains`, applies on top of archetype's section selection. Brewfile stays plain.
   - **Option C — Section markers**: in canonical Brewfile, add comments like `# feature:docker-desktop` next to specific lines; customize-brewfile.sh filters by feature flags from chezmoi data.

   B is least invasive (preserves Brewfile.local lifecycle), C is most discoverable, A is most powerful but requires chezmoi-managing Brewfile.

4. **Feature toggle UX**: how does user change a flag?
   - `dot apply --enable=docker-desktop` writes to chezmoi data + triggers apply
   - Manual edit `~/.config/chezmoi/chezmoi.toml` + `dot apply`
   - Interactive `bootstrap.sh customize` extended with feature menu

5. **Default values**: какие flags ON по умолчанию? Должны соответствовать тому что в canonical Brewfile сейчас (zero-config = no behavior change for existing users).

6. **Scope creep** — feature flags только для Brewfile, или ещё:
   - LaunchAgents: enable/disable specific autostart items
   - macOS defaults: enable/disable specific tweaks (e.g. `dark_mode_force = false`)
   - SSH/git: alternative configs per flag
   
   Recommend: Brewfile only for slice 2d. Other dimensions = slice 2e+ if useful.

## Suggested initial feature set

5-7 toggles to start (small to validate the mechanism):
- `docker_desktop` — adds/removes docker brew formula + cask
- `jetbrains` — toggle JetBrains Toolbox
- `local_llm` — ollama + ollama-models + open-webui? Or just ollama
- `vpn` — VPN clients (currently in Brewfile section "Networking / VPN / remote")
- `office` — Microsoft Office for Mac

## File-touch (preliminary)

| Task | Files | Notes |
|------|-------|-------|
| 1 — Data shape + chezmoi.toml.tmpl | `chezmoi/.chezmoi.toml.tmpl` | Add `[data.features]` block with defaults, `promptBoolOnce` per feature OR single multi-select |
| 2 — Brewfile integration (depends on Design #3 choice) | Option A: rename `Brewfile` → `Brewfile.tmpl`, chezmoi-manage. Option B: extend customize-brewfile.sh. Option C: marker syntax + customize-brewfile.sh filter | Big design call |
| 3 — `dot apply --enable=X --disable=Y` flag | `chezmoi/dot_local/bin/executable_dot` or `scripts/dot-apply.sh` (from slice 2c) | Writes to chezmoi data, triggers apply |
| 4 — bootstrap.sh `customize` extension | `bootstrap.sh` | Optional: interactive feature menu |
| 5 — Docs | README.md, docs/usage.md | Feature list, how to toggle, how to add new ones |

## Predecessors / context to read

- [v_2026-05-16-dot-cli-archetypes-design.md](v_2026-05-16-dot-cli-archetypes-design.md) — archetype design and Brewfile lifecycle
- (slice 2c plan once it ships and is renamed `v_*`) — `dot apply` semantics
- `Brewfile` — current canonical file, section markers (`# ── Title ──`)
- `scripts/customize-brewfile.sh` — current archetype-based section selection

## Special requirements (same as slice 2c)

1. **CWD-drift defense in agent prompts** (absolute paths + `git -C` + branch confirm at top of report).
2. **Mandatory git diff paste for doc tasks**.
3. **Phase 8.5 advisor call** before Phase 9.
4. **chezmoi promptBoolOnce/promptChoiceOnce TTY caveat**: defaults don't save in non-TTY context. Plan accordingly.

## Suggested execution flow

After Phase 0 brainstorm settles on Design #3 (integration mechanism), the rest is small:

- Wave 1: Task 1 (data shape) + Task 2 (Brewfile integration) — sequential because both touch chezmoi data layer
- Wave 2: Task 3 (`dot apply` flag) — depends on slice 2c being complete
- Wave 3: Task 4 (bootstrap customize) — optional, can ship in slice 2e
- Wave 4: Task 5 (docs)

5-7 commits expected. Sonnet for design-heavy tasks (1, 2, 3), Haiku for mechanical (4, 5).
