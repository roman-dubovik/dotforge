# Design: dotforge public launch — README, landing page, curl-installer, ROADMAP, CHANGELOG, `dot setup`

Date: 2026-05-18
Status: READY TO EXECUTE

## Goal

Подготовить dotforge к публичной презентации по образцу `arch-graph`:

1. Перепаковать `README.md` в полноценный landing-документ.
2. Добавить GitHub Pages site (`docs/index.html` + CSS + JS).
3. Добавить curl-installer (`docs/install.sh`) — самодостаточный для свежего Mac.
4. Добавить `ROADMAP.md` + `CHANGELOG.md`.
5. Добавить `dot setup` подкоманду как alias для `bootstrap.sh setup`.

Финальный UX:

- **На новом Mac:** `curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/docs/install.sh | bash`
- **На уже настроенном Mac:** `dot pull` (есть) / `dot apply` (есть) / `dot doctor` (есть).
- **Если кто-то уже склонил репо вручную:** `./bootstrap.sh setup` ИЛИ `dot setup` (новый alias).

## Repo facts (from Phase 1 research)

**GitHub:** `https://github.com/roman-dubovik/dotforge`
**Default branch:** `main`
**Platform:** macOS only (Darwin)
**Prereqs:** curl + bash 3.2 (всё что есть в свежем macOS из коробки)

**Команды сегодня:**

| Layer | Команда | Что делает |
|-------|---------|-----------|
| bootstrap.sh | setup | Полный bootstrap: Xcode CLT, brew, chezmoi init, prompts, chezmoi apply |
| bootstrap.sh | update | git pull + chezmoi apply |
| bootstrap.sh | sync | Promote local brew + /Applications → canonical Brewfile |
| bootstrap.sh | customize | Interactive Brewfile section picker + feature flags |
| bootstrap.sh | add-key | Upload SSH keys в Bitwarden |
| bootstrap.sh | scan-cli / scan-macos / scan-autostart | Standalone scanners |
| bootstrap.sh | doctor | = `dot doctor` |
| bootstrap.sh | fork | Personalize-for-own-account flow |
| bootstrap.sh | browse | Interactive walkthrough |
| `dot` | doctor | 8 read-only sync checks |
| `dot` | apply | chezmoi apply + before/after doctor delta, `--dry-run` |
| `dot` | snapshot | scan-cli + scan-login + scan-macos → commit |
| `dot` | pull | fetch + ff-only + apply + doctor (strict) |
| `dot` | version / help | служебные |
| `dot` | **setup** ← ДОБАВЛЯЕМ | alias для bootstrap.sh setup |

**Feature flags** (в `chezmoi.toml.tmpl`, блок `[data.features]`):
- `docker_desktop` (default true)
- `ai_assistants` (default true)
- `vpn_suite` (default true)
- `office_suite` (default **false**)
- `media_tools` (default true)
- `design_tools` (default true)

**Archetypes:** `full` / `minimal-dev` / `cli-server` / `custom`.

**Scanners → output:**
- `scan-cli.sh --capture` → `cli-globals.txt`
- `scan-login-autostart.sh --capture` → `login-items.txt`
- `scan-macos-defaults.sh --capture` → `chezmoi/dot_config/dotforge/macos-defaults.txt`

**chezmoi hooks** (в `chezmoi/.chezmoiscripts/`):
- `run_once_before_10-install-bw.sh`
- `run_onchange_20-apply-brewfile.sh.tmpl`
- `run_onchange_25-install-curl-toolchains.sh`
- `run_onchange_30-install-cli-globals.sh.tmpl`
- `run_onchange_50-pull-ssh-keys.sh.tmpl`
- `run_onchange_60-apply-macos-defaults.sh.tmpl`
- `run_onchange_70-apply-login-autostart.sh`

**Shipped slices:**
- Plan 1 (Foundation) — Xcode CLT, brew, Brewfile, chezmoi dotfiles, SSH, Claude config, `fork`.
- Plan 1.5 — curl-toolchains (oh-my-zsh, p10k, nvm, pnpm, maestro), macOS defaults baseline.
- Slice 1 — `bootstrap.sh doctor` (read-only diagnostic, 8 checks).
- Slice 2a — `dot` CLI namespace (chezmoi-managed shim + doctor/help/version).
- Slice 2b — Persistent Brewfile archetypes (4 choices, prompted on init).
- Slice 2c — `dot apply` / `dot snapshot` / `dot pull` (loop-closing trio).
- Slice 2d — Feature flags (6) + scan-macos `--capture` + bats tests.

**Deferred:**
- Slice 2e — программный `dot apply --enable=X --disable=Y`, `local_llm` flag, persisted bootstrap menu.
- Plan 3 (Multi-machine sync) — активная reconciliation между машинами.
- App-specific configs (Raycast, IDE settings, Hammerspoon, Rectangle).
- Browser/mail/app logins (limited by Apple platform constraints).

## arch-graph style reference (Phase 1 finding)

**README structure (что нужно повторить):**
- Hero: project name + 1-line tagline.
- `## What's new (May 2026)` — список последних shipped фич.
- `## Install` — curl one-liner + git clone + manual fallback + verify.
- `## Quick start` — пошаговый wizard с примером сессии.
- `## What you get` — table коммандная + feature matrix со статусами (✅/🚧/📅).
- `## Commands` — table с full reference.
- `## Limitations & honesty` — что НЕ делает + почему.
- `## Adjacent tools` — сравнение с альтернативами (nix-darwin, chezmoi alone, etc).
- `## Development` — как развивать.
- `## License` — MIT.

**index.html structure:**
- Dark theme (#0a0a0f bg, #8b9eff accent — это arch-graph; для dotforge ВЫБРАТЬ СВОЮ ПАЛИТРУ).
- Hero с animated SVG.
- Sections: Problem / How it works / Commands / Install / Roadmap / GitHub CTA.
- Google Fonts: Inter (sans) + JetBrains Mono (code).
- 4 stat cards в hero (для dotforge можно: «N команд», «6 feature flags», «4 archetypes», «3 scanners»).

**install.sh skeleton:**
- POSIX `#!/bin/sh`, `set -e`.
- Steps: OS check → Xcode CLT → brew → clone-or-update repo → exec bootstrap.sh setup.
- Env-vars: `DOTFORGE_REPO_URL` / `DOTFORGE_BRANCH` / `DOTFORGE_MACHINE_NAME` / `DOTFORGE_PROFILE` / `DOTFORGE_BREWFILE_ARCHETYPE`.
- Idempotent: pull --ff-only if repo exists.
- Interactive TTY detection (`/dev/tty` fallback для `curl | bash`).

## Task breakdown

### Task 1 — `dot setup` subcommand
- **Complexity:** Simple
- **Model:** haiku
- **Files:** `chezmoi/dot_local/bin/executable_dot`
- **Pattern:** скопировать структуру существующих case-веток (`apply`/`pull`).
- **What:** Добавить `setup` ветку в case-statement; exec `bash $REPO_DIR/bootstrap.sh setup "$@"`. Обновить help-секцию.
- **AC:**
  1. `dot setup` исполняется и эквивалентен `bootstrap.sh setup` (передаёт env-vars и аргументы).
  2. `dot help` показывает `setup` в списке команд.
  3. Bash 3.2 совместимость (не использовать declare -A, [[ ]] для regex, и т.п.).
  4. Существующие команды (`doctor`/`apply`/`snapshot`/`pull`) не сломаны.
- **NOT in scope:** изменения в `bootstrap.sh setup` — только alias.
- **Tests:** N/A (config-shim). Smoke: `dot setup --help` должно показать setup help.

### Task 2 — `docs/install.sh` curl-installer
- **Complexity:** Medium
- **Model:** sonnet
- **Files:** `docs/install.sh` (new)
- **Pattern:** структура arch-graph `docs/install.sh`, адаптированная под bash/macOS.
- **What:** Self-contained installer, который:
  1. Проверяет macOS (`uname` = Darwin).
  2. Устанавливает Xcode CLT (если нет) — invoke `xcode-select --install` + ожидание.
  3. Устанавливает brew (если нет) — NONINTERACTIVE curl install.
  4. Устанавливает git (если нет) — `brew install git`.
  5. Клонирует репо в `${DOTFORGE_INSTALL_DIR:-$HOME/dotforge}` (или `git pull --ff-only` если есть).
  6. `exec bash $INSTALL_DIR/bootstrap.sh setup` с пробросом env-vars.
- **Env-var overrides:** `DOTFORGE_REPO_URL`, `DOTFORGE_BRANCH`, `DOTFORGE_INSTALL_DIR`.
- **AC:**
  1. `set -e` + clear error messages с emoji статусом (✓/⚠/✗).
  2. POSIX-compatible (`/bin/sh` shebang, no bash-isms).
  3. Идемпотентный: повторный запуск — pull + apply, не clone-on-top.
  4. TTY-aware: работает при `curl | bash` (re-opens `/dev/tty` для prompts).
  5. Пробрасывает env-vars в `bootstrap.sh setup` (через export перед exec).
  6. Один-в-один работает для команды из README: `curl -fsSL ...docs/install.sh | bash`.
- **NOT in scope:** изменения в `bootstrap.sh setup` или в chezmoi hooks.
- **Tests:** N/A (shell installer). Smoke: `bash -n docs/install.sh` (syntax check) + dry-run review.

### Task 3 — `CHANGELOG.md`
- **Complexity:** Simple
- **Model:** haiku
- **Files:** `CHANGELOG.md` (new)
- **Pattern:** [Keep a Changelog](https://keepachangelog.com/) format с разбивкой по слайсам.
- **What:** Структурированный changelog с разбивкой:
  - `## [Unreleased]` — пусто или текущая работа.
  - `## [Slice 2d] - 2026-05-17` — feature flags + macOS capture.
  - `## [Slice 2c] - 2026-05-16` — dot apply/snapshot/pull.
  - `## [Slice 2b] - 2026-05-XX` — Brewfile archetypes.
  - `## [Slice 2a] - 2026-05-XX` — dot CLI namespace.
  - `## [Slice 1] - 2026-05-XX` — dot doctor.
  - `## [Plan 1.5] - 2026-04-XX` — curl-toolchains + macOS baseline.
  - `## [Plan 1] - 2026-04-XX` — Foundation (Xcode CLT, brew, chezmoi).
- **Source of truth:** `git log --oneline -100`, плюс v_*-design.md файлы.
- **AC:**
  1. Каждый slice имеет дату (или приближённую) и список изменений (Added/Changed/Fixed).
  2. Ссылки на key files (`scripts/dot-apply.sh`, etc.).
  3. Markdown валиден (без сломанных ссылок).
- **NOT in scope:** конкретные commit hashes (не нужны в публичном CHANGELOG).
- **Tests:** N/A (doc).

### Task 4 — `ROADMAP.md`
- **Complexity:** Simple
- **Model:** haiku
- **Files:** `ROADMAP.md` (new)
- **Pattern:** arch-graph ROADMAP.md — секции «Where we are / Shipped / What's next / Deferred / Open questions».
- **What:**
  - `## Where we are` — 1 para, что dotforge делает сейчас.
  - `## Shipped` — Plans 1/1.5/2a/2b/2c/2d с одной строкой каждый.
  - `## What's next` — Slice 2e (приоритет 1), Plan 3 multi-machine sync (приоритет 2), app-specific configs (приоритет 3).
  - `## Deferred / non-goals` — что мы НЕ делаем (Linux, Windows, full GUI restore).
  - `## Known limits (honest)` — список из README → выделено.
  - `## Open questions` — например, persistent menu, archetype migration.
- **AC:**
  1. Соответствует фактическому статусу (shipped vs deferred per design doc).
  2. Priority markers (🟢 / 🟡 / ⚪) как в arch-graph.
  3. Honest framing (не overpromising).
- **NOT in scope:** конкретные timeline / due dates.
- **Tests:** N/A.

### Task 5 — `README.md` (full rewrite)
- **Complexity:** Medium
- **Model:** sonnet
- **Files:** `README.md` (полная перезапись)
- **Pattern:** arch-graph README структура (см. «arch-graph style reference» выше).
- **What:** Структура:
  1. **Hero** — `# dotforge` + tagline + 1 SVG/ASCII диаграмма + project shields-like one-liner.
  2. `## What's new (May 2026)` — bullets из slice 2c+2d.
  3. **Paragraph:** что такое dotforge + сравнение с chezmoi/nix-darwin.
  4. `## Install` —
     - **New Mac (curl):** `curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/docs/install.sh | bash`
     - **Existing repo (manual):** `git clone https://github.com/roman-dubovik/dotforge && cd dotforge && ./bootstrap.sh setup` ИЛИ после первой установки — `dot setup`.
     - **Verify:** `dot doctor`.
     - **Uninstall:** инструкция (chezmoi forget + cleanup symlinks).
  5. `## Quick start` — interactive wizard transcript:
     - `./bootstrap.sh setup` → prompts (machine name, profile, archetype, feature flags) → `chezmoi apply` runs.
  6. `## How it works` — ASCII flow diagram (тот, что уже использовался ранее в сессии):
     ```
     bootstrap.sh setup ─┐
                         ▼
                  chezmoi init+apply ─┬─→ Brewfile → brew bundle
                                      ├─→ macOS defaults → defaults write
                                      ├─→ SSH keys ← Bitwarden
                                      ├─→ Login items → osascript
                                      └─→ dot CLI → ~/.local/bin/dot
                                                       │
                                                       ▼
                                              dot doctor / apply / snapshot / pull
     ```
  7. `## Commands` — full reference table (см. Repo facts выше).
  8. `## Feature flags` — table с 6 флагами + дефолтами.
  9. `## Archetypes` — table с 4 archetypes + что включают.
  10. `## Scanners` — table с 3 scanners + output files.
  11. `## chezmoi hooks` — table с 7 hooks + что триггерят.
  12. `## Cross-machine sync` — `dot snapshot` → git push → на другой машине `dot pull`. ASCII flow.
  13. `## Feature matrix` — table «фича → статус» (✅ / 🚧 / 📅) — ссылается на ROADMAP/CHANGELOG.
  14. `## Limitations & honesty` — список deferred + не делает (Linux, Windows, full app sync).
  15. `## Adjacent tools` — comparison grid: dotforge vs (chezmoi alone, nix-darwin, dotbot, mackup).
  16. `## Development` — git clone, как добавить feature flag, как обновить ROADMAP.
  17. `## License` — MIT.
- **AC:**
  1. Все command examples из таблицы валидны (можно скопировать и запустить).
  2. ASCII диаграммы рендерятся в GitHub Markdown (без поломанных box-drawing chars).
  3. Все feature flags, archetypes, scanners, hooks упомянуты с правильными file paths.
  4. Линки на CHANGELOG.md, ROADMAP.md, docs/index.html работают.
  5. Curl one-liner работает с публичным URL.
  6. Length: 300-450 строк (как arch-graph 441).
  7. Tone: honest, technical, без маркетингового флера.
- **NOT in scope:** изменения в коде команд (только описание).
- **Tests:** N/A.

### Task 6 — `docs/index.html` + `docs/styles.css` + `docs/scripts.js`
- **Complexity:** Medium
- **Model:** sonnet
- **Skill to use:** `frontend-design` (для distinctive landing, не generic AI-aesthetic)
- **Files:** `docs/index.html`, `docs/styles.css`, `docs/scripts.js`, `docs/.nojekyll`
- **Pattern:** arch-graph `docs/index.html` — структурно, но СВОЯ цветовая палитра (dotforge ≠ arch-graph).
- **What:**
  - Color palette: тёплая «forge»-тема (orange/amber + dark slate) или cool «git»-тема (deep teal + amber accent). Сам выбери — главное чтобы было distinctive, не клон arch-graph.
  - Sections:
    1. Header: `dotforge` logo (SVG) + nav (Install, How, Commands, Roadmap, GitHub).
    2. Hero: animated SVG (forge/hammer/anvil OR network nodes OR terminal-prompt — на выбор), tagline (1 строка), 2 CTAs (Install / View on GitHub), 4 stat cards («N команд», «6 feature flags», «4 archetypes», «3 scanners»).
    3. Problem: 1-para про «свежий Mac → 20 часов кликов / нет, dotforge».
    4. How it works: SVG flow diagram (bootstrap → chezmoi → 7 hooks → dot CLI).
    5. Install: copy-able curl one-liner + git clone fallback + verify.
    6. Commands: 2-column grid с командами и описаниями (compact).
    7. Roadmap: shipped + next, с цветными статус-маркерами.
    8. CTA footer: GitHub + License + Contribute.
  - JS: copy-button для curl one-liner, smooth scroll для nav.
- **AC:**
  1. Открывается в Safari/Chrome без ошибок в console.
  2. Mobile-responsive (один-column layout на narrow viewports).
  3. Все curl/git команды копируются по клику.
  4. Dark theme (matches dotforge dev-tool vibe).
  5. Inline SVG (нет внешних image dependencies — чтобы работало на GitHub Pages без `.nojekyll` гимнастики).
  6. Google Fonts: Inter + JetBrains Mono (как arch-graph).
  7. Готов к GitHub Pages publish (`docs/` branch → `main / docs` setting).
- **NOT in scope:** аналитика, телеметрия, internationalization, interactive demos.
- **Tests:** N/A (smoke: open `docs/index.html` в браузере, проверить console + responsive).

## File-touch matrix

| Task | Files | Type |
|------|-------|------|
| 1 — `dot setup` | `chezmoi/dot_local/bin/executable_dot` | edit |
| 2 — install.sh | `docs/install.sh` | new |
| 3 — CHANGELOG | `CHANGELOG.md` | new |
| 4 — ROADMAP | `ROADMAP.md` | new |
| 5 — README | `README.md` | rewrite |
| 6 — Pages site | `docs/index.html`, `docs/styles.css`, `docs/scripts.js`, `docs/.nojekyll` | new |

**No file overlap** — tasks technically parallelizable. Но Task 5 (README) references CHANGELOG.md + ROADMAP.md + docs/install.sh + dot setup → wave-based execution гарантирует, что README не упомянет несуществующее.

## Patterns to follow

- **Bash 3.2 compatibility:** не использовать `declare -A`, `[[ str =~ regex ]]` (если regex сложный), `mapfile`. Использовать parallel indexed arrays + lookup loops, fixed-width substring extraction (`${line:7:22}`).
- **Сохранять existing CLAUDE.md conventions:** Conventional Commits в формате `feat(scope):` / `fix(scope):` / `docs(scope):`.
- **Атомарные коммиты:** один task = один или 2-3 коммита (никаких 10-в-1).
- **Brand consistency:** название проекта везде = `dotforge` (lowercase, без emoji в названии). GitHub handle = `roman-dubovik`.

## External constraints

- macOS-only target. Не упоминать Linux/Windows как «future».
- bash 3.2 (default /bin/bash на macOS) для shell-скриптов; zsh для interactive shell у пользователя.
- chezmoi — основной dotfiles-движок, не заменяется.
- Bitwarden — единственный credential store, не заменяется на 1Password/etc.
- Brewfile + brew bundle — единственный package manager для GUI/CLI apps.
- GitHub Pages serving из `docs/` folder в `main` branch — **проверь, что `docs/.nojekyll` создан** (без него Jekyll съест файлы с подчёркиваниями).

## Open questions

Никаких — все ответы получены в Phase 0.

## Acceptance Criteria — global (verify after all tasks)

1. **Curl one-liner работает end-to-end** (smoke в VM или dry-run review): `curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/docs/install.sh | bash` — должен корректно стартовать (не падать на синтаксисе).
2. **`dot setup` работает** в существующей установке.
3. **`dot setup --help`** показывает помощь (или пробрасывает в bootstrap.sh setup).
4. **README рендерится корректно в GitHub UI** (нет broken markdown).
5. **GitHub Pages preview:** `python3 -m http.server 8000` в `docs/` → `localhost:8000` показывает landing без console errors.
6. **Все internal ссылки работают:** README → CHANGELOG, ROADMAP, docs/install.sh, docs/index.html.
7. **CHANGELOG и ROADMAP соответствуют фактическому состоянию** (shipped slices правильно перечислены).
8. **`dot doctor` всё ещё проходит** (никаких regressions).
