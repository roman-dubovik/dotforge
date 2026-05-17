#!/usr/bin/env bash
# Mac dotfiles bootstrap.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/roman-dubovik/dotforge/main/bootstrap.sh | bash
#
# Direct subcommands (skip the menu):
#   bootstrap.sh setup       # full Mac bootstrap
#   bootstrap.sh update      # chezmoi update + apply
#   bootstrap.sh sync        # promote local extras into the canonical Brewfile
#   bootstrap.sh customize   # re-pick Brewfile sections
#   bootstrap.sh add-key     # upload SSH keys to Bitwarden (bulk or single)
#   bootstrap.sh scan-cli    # classify everything in PATH; capture globals
#   bootstrap.sh scan-macos      # print current macOS defaults as defaults write commands
#   bootstrap.sh scan-autostart  # dump current login items + LaunchAgents
#   bootstrap.sh doctor       # run diagnostic checks (read-only)
#   bootstrap.sh fork        # clone+personalize this repo under your own GitHub
#   bootstrap.sh browse      # read-only walkthrough

set -euo pipefail

REPO="roman-dubovik/dotforge"
REPO_BRANCH="main"
REPO_URL="https://github.com/$REPO"
RAW_URL="https://raw.githubusercontent.com/$REPO/$REPO_BRANCH"

# ── Helpers ──
say() { printf "\n→ %s\n" "$*"; }
ok()  { printf "  ✓ %s\n" "$*"; }
err() { printf "  ✗ %s\n" "$*" >&2; exit 1; }

# ── Pre-flight (always runs) ──

preflight() {
    if [[ "$(uname)" != "Darwin" ]]; then
        err "This bootstrap is for macOS only."
    fi

    if [[ "$(uname -m)" != "arm64" && "$(uname -m)" != "x86_64" ]]; then
        err "Unsupported architecture: $(uname -m)"
    fi
}

# ── Idempotent installers ──

install_xcode_clt() {
    if xcode-select -p >/dev/null 2>&1; then
        ok "Xcode CLT already installed"
        return 0
    fi
    say "Installing Xcode Command Line Tools (GUI dialog will appear)..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
        printf "."
    done
    printf "\n"
    ok "Xcode CLT installed"
}

install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        ok "Homebrew already installed"
        return 0
    fi
    say "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
}

install_bootstrap_deps() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && pkgs=(chezmoi bitwarden-cli yq gum)
    say "Installing dependencies: ${pkgs[*]}"
    for pkg in "${pkgs[@]}"; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
            ok "$pkg already installed"
        else
            brew install "$pkg"
            ok "Installed $pkg"
        fi
    done
}

# ── State detection ──

state_chezmoi_initialized() {
    [[ -f "$HOME/.config/chezmoi/chezmoi.toml" ]]
}

# Echoes the repo-root path (the directory containing Brewfile and scripts/)
# if chezmoi has cloned the repo; empty string otherwise.
get_repo_root() {
    state_chezmoi_initialized || { printf ""; return; }
    local sp
    sp="$(chezmoi source-path 2>/dev/null)" || { printf ""; return; }
    printf "%s" "${sp%/chezmoi}"
}

# ── Top-level menu ──

show_main_menu() {
    local initialized="no"
    state_chezmoi_initialized && initialized="yes"

    local header
    if [[ "$initialized" == "no" ]]; then
        header="What would you like to do? (Setup is the natural first step on a fresh Mac.)"
    else
        header="What would you like to do? (chezmoi is already initialized on this machine.)"
    fi

    gum choose --header "$header" \
        "setup     — Set up this Mac (full bootstrap)" \
        "update    — Pull latest dotfiles from remote and re-apply" \
        "sync      — Promote local extras (brew + /Applications) into Brewfile" \
        "customize — Re-pick which Brewfile sections to install" \
        "add-key   — Upload a new SSH key to Bitwarden (profile or machine scope)" \
        "scan-cli  — Classify everything in PATH; capture CLI globals" \
        "scan-macos    — print current macOS defaults as defaults write commands" \
        "scan-autostart — dump current login items + LaunchAgents" \
        "doctor    — Run diagnostic checks against canonical state (read-only)" \
        "fork      — Make your own dotforge for a different GitHub account" \
        "browse    — Read-only walkthrough of what's available" \
        "exit      — Quit"
}

# ── Subcommand: setup ──

cmd_setup() {
    say "Full Mac bootstrap"

    # Bigger dep install (full set this time)
    install_bootstrap_deps chezmoi bitwarden-cli yq gum

    say "Configure this machine"

    local default_machine_name machine_name profile brewfile_archetype
    default_machine_name="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
    machine_name="$(gum input --prompt "Machine name (human-friendly): " --value "$default_machine_name")"
    [[ -z "$machine_name" ]] && err "Machine name required"

    profile="$(gum choose --header "Profile:" personal work)"
    [[ -z "$profile" ]] && err "Profile required"

    brewfile_archetype="$(gum choose --header "Brewfile archetype (Brewfile selection preset):" \
        "full" "minimal-dev" "cli-server" "custom")"
    [[ -z "$brewfile_archetype" ]] && err "Brewfile archetype required"

    ok "Machine: $machine_name, profile: $profile, archetype: $brewfile_archetype"

    say "Login to Bitwarden (master password required)"

    if bw status 2>/dev/null | grep -q '"status":"unauthenticated"'; then
        BW_SESSION="$(bw login --raw)"
    else
        BW_SESSION="$(bw unlock --raw)"
    fi
    export BW_SESSION
    [[ -z "$BW_SESSION" ]] && err "Bitwarden session is empty"

    trap 'bw lock >/dev/null 2>&1 || true' EXIT
    ok "Bitwarden unlocked"

    say "Cloning dotfiles repo..."
    chezmoi init "$REPO" \
        --branch "$REPO_BRANCH" \
        --promptString "machine_name=$machine_name" \
        --promptChoice "profile=$profile" \
        --promptChoice "brewfile_archetype=$brewfile_archetype"

    local repo_root
    repo_root="$(get_repo_root)"
    [[ -z "$repo_root" ]] && err "chezmoi source-path is empty after init"

    if [[ "$brewfile_archetype" == "custom" ]]; then
        say "Brewfile customization (interactive — archetype=custom)"
        if gum confirm --default=Yes "Customize what gets installed (pick sections)?"; then
            bash "$repo_root/scripts/customize-brewfile.sh" --no-install
            ok "Brewfile.local written. The brewfile hook will use it during apply."
        else
            ok "Skipped customizer — canonical Brewfile will be used."
        fi
    else
        ok "Archetype '$brewfile_archetype' selected — Brewfile.local will be auto-generated by the hook."
    fi

    say "Applying chezmoi configuration..."
    chezmoi apply -v

    ok "chezmoi apply complete"
    say "Done! Restart your shell to pick up new configuration."
}

# ── Subcommand: update ──

cmd_update() {
    if ! state_chezmoi_initialized; then
        err "chezmoi is not initialized yet. Run 'setup' first."
    fi
    say "Pulling latest dotfiles and re-applying..."
    chezmoi update -v
    ok "Update complete."
}

# ── Subcommand: sync ──

cmd_sync() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/sync-brewfile.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi
    bash "$repo_root/scripts/sync-brewfile.sh"
}

# ── Subcommand: customize ──

cmd_customize() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/customize-brewfile.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi

    local feature_args=()

    # Feature names and their defaults (bash 3.2 compat: parallel indexed arrays, no -A).
    # Order must be consistent across all three arrays.
    local features=(docker_desktop ai_assistants vpn_suite office_suite media_tools design_tools)
    local defaults=(true         true          true      false        true         true)

    # Read current values from chezmoi.toml; fall back to defaults if absent.
    local chezmoi_toml="$HOME/.config/chezmoi/chezmoi.toml"
    local current_values=()
    local i
    for i in "${!features[@]}"; do
        local f="${features[$i]}" def="${defaults[$i]}" v=""
        if [[ -f "$chezmoi_toml" ]]; then
            v="$(grep -E "^[[:space:]]*${f}[[:space:]]*=" "$chezmoi_toml" 2>/dev/null \
                 | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | head -1 || true)"
        fi
        [[ -z "$v" ]] && v="$def"
        current_values+=("$v")
    done

    if [[ -t 0 ]] && command -v gum >/dev/null 2>&1; then
        # Build pre-selected CSV: feature names where current value is true.
        local preselect=""
        for i in "${!features[@]}"; do
            if [[ "${current_values[$i]}" == "true" ]]; then
                [[ -n "$preselect" ]] && preselect+=","
                preselect+="${features[$i]}"
            fi
        done

        say "Select feature flags (space toggles, enter confirms):"
        local selected_csv
        if ! selected_csv="$(printf "%s\n" "${features[@]}" \
            | gum choose --no-limit --selected="$preselect" \
                --header "Feature flags (space=toggle, enter=confirm)")"; then
            say "Menu cancelled — keeping current feature flags."
        else
            # Normalize newline-separated gum output to a comma-delimited membership set.
            local selected_list
            selected_list="${selected_csv//$'\n'/,},"  # trailing comma for grep
            local f
            for f in "${features[@]}"; do
                if [[ ",${selected_list}" == *",${f},"* ]]; then
                    feature_args+=("--enable=${f}")
                else
                    feature_args+=("--disable=${f}")
                fi
            done
        fi
    elif [[ ! -t 0 ]]; then
        # Non-TTY: skip menu entirely, let customize-brewfile use its own defaults.
        say "Non-interactive mode (no TTY): skipping feature menu, using defaults from chezmoi data."
    else
        # TTY but no gum: ask y/n for each feature.
        say "gum not found — entering feature flags one by one (y/n):"
        local f def_val prompt_val yn
        for i in "${!features[@]}"; do
            f="${features[$i]}"
            def_val="${current_values[$i]}"
            if [[ "$def_val" == "true" ]]; then
                prompt_val="Y/n"
            else
                prompt_val="y/N"
            fi
            read -r -p "  Enable ${f}? [${prompt_val}] " yn </dev/tty
            yn="${yn:-$def_val}"
            case "$yn" in
                [yY]*|true)  feature_args+=("--enable=${f}") ;;
                *)           feature_args+=("--disable=${f}") ;;
            esac
        done
    fi

    bash "$repo_root/scripts/customize-brewfile.sh" ${feature_args[@]+"${feature_args[@]}"}
    say "If you want to apply the new Brewfile.local now, run:"
    echo "  chezmoi apply --include=scripts -v"
}

# ── Subcommand: add-key ──

cmd_add_key() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/add-ssh-key.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi

    # Make sure bw is unlocked. If BW_SESSION is empty, prompt for unlock.
    if [[ -z "${BW_SESSION:-}" ]] || ! bw_is_unlocked; then
        say "Unlocking Bitwarden..."
        if bw status 2>/dev/null | grep -q '"status":"unauthenticated"'; then
            BW_SESSION="$(bw login --raw)"
        else
            BW_SESSION="$(bw unlock --raw)"
        fi
        export BW_SESSION
        trap 'bw lock >/dev/null 2>&1 || true; unset BW_SESSION' EXIT
    fi

    bash "$repo_root/scripts/add-ssh-key.sh" "$@"
}

# Used by cmd_add_key — pulled from lib/secrets.sh if available, else fallback.
bw_is_unlocked() {
    bw status 2>/dev/null | grep -q '"status":"unlocked"'
}

# ── Subcommand: scan-cli ──

cmd_scan_cli() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/scan-cli.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi
    bash "$repo_root/scripts/scan-cli.sh" "$@"
}

# ── Subcommand: scan-macos ──

cmd_scan_macos() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/scan-macos-defaults.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi
    bash "$repo_root/scripts/scan-macos-defaults.sh" "$@"
}

# ── Subcommand: scan-autostart ──

cmd_scan_autostart() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/scan-login-autostart.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi
    bash "$repo_root/scripts/scan-login-autostart.sh" "$@"
}

# ── Subcommand: doctor ──

cmd_doctor() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" || ! -x "$repo_root/scripts/doctor.sh" ]]; then
        err "Repo not cloned yet (run 'setup' first)."
    fi
    DOTFORGE_BRANCH="$REPO_BRANCH" bash "$repo_root/scripts/doctor.sh" "$@"
}

# ── Subcommand: fork ──
#
# Clones roman-dubovik/dotforge to a target directory, then runs the
# personalize-fork.sh helper to find/replace user-specific strings and
# (optionally) create the user's own GitHub repo + push.
cmd_fork() {
    gum style --foreground 212 --bold --margin "1 0" "dotforge — make your own"
    gum style --foreground 245 \
"This will clone $REPO into a directory you choose, then walk you through" \
"personalizing it for your GitHub account, name, and email. At the end the" \
"script will offer to create the new repo on GitHub and push." \
"" \
"You'll be asked for confirmation at every important step." \
"Nothing is pushed remotely until you say yes."

    local default_dir="$HOME/Documents/Projects/dotforge-mine"
    local target_dir
    target_dir="$(gum input --prompt "Target directory for the clone: " --value "$default_dir")"
    [[ -z "$target_dir" ]] && err "Target directory required"

    if [[ -e "$target_dir" ]]; then
        gum style --foreground 220 "  ! $target_dir already exists."
        if gum confirm --default=No "Remove it and re-clone? (irreversible)"; then
            rm -rf "$target_dir"
            ok "Removed $target_dir"
        else
            err "Aborted (path already exists)."
        fi
    fi

    gum style --foreground 212 --bold "→ Cloning"
    gum style --foreground 245 "  $REPO_URL.git  →  $target_dir"
    git clone --depth=1 "$REPO_URL.git" "$target_dir"
    ok "Cloned."

    # Hand off to the personalize script. All remaining args propagate so
    # callers can pre-fill (--gh-user, --name, --email, etc.) and skip
    # those prompts.
    bash "$target_dir/scripts/personalize-fork.sh" "$@"
}

# ── Subcommand: browse ──

# Fetch a file either from the cloned repo (preferred) or via curl from
# raw.githubusercontent.com (fallback for fresh-Mac browse). Echoes the
# local path; the caller should pass it to gum pager.
fetch_for_browse() {
    local rel="$1" repo_root
    repo_root="$(get_repo_root)"
    if [[ -n "$repo_root" && -f "$repo_root/$rel" ]]; then
        printf "%s" "$repo_root/$rel"
        return 0
    fi
    local out
    out="$(mktemp -t "dotforge-browse.XXXXXX")"
    if curl -fsSL "$RAW_URL/$rel" -o "$out"; then
        printf "%s" "$out"
    else
        rm -f "$out"
        return 1
    fi
}

view_brewfile() {
    local f
    if ! f="$(fetch_for_browse Brewfile)"; then
        printf "  ✗ Could not fetch Brewfile\n" >&2
        return 1
    fi
    gum pager < "$f"
}

view_usage_doc() {
    local f
    if ! f="$(fetch_for_browse docs/usage.md)"; then
        printf "  ✗ Could not fetch docs/usage.md\n" >&2
        return 1
    fi
    gum pager < "$f"
}

view_state() {
    local lines=()
    if state_chezmoi_initialized; then
        lines+=("chezmoi config: $HOME/.config/chezmoi/chezmoi.toml")
        local profile machine
        profile="$(grep -E '^[[:space:]]*profile[[:space:]]*=' "$HOME/.config/chezmoi/chezmoi.toml" | sed 's/.*"\(.*\)".*/\1/' || true)"
        machine="$(grep -E '^[[:space:]]*machine_name[[:space:]]*=' "$HOME/.config/chezmoi/chezmoi.toml" | sed 's/.*"\(.*\)".*/\1/' || true)"
        lines+=("  profile     = ${profile:-?}")
        lines+=("  machine_name = ${machine:-?}")
    else
        lines+=("chezmoi: NOT initialized (run 'setup' first)")
    fi

    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -n "$repo_root" ]]; then
        lines+=("repo root:    $repo_root")
        lines+=("Brewfile:     $repo_root/Brewfile")
        if [[ -f "$repo_root/Brewfile.local" ]]; then
            lines+=("Brewfile.local: $repo_root/Brewfile.local (active customization)")
        else
            lines+=("Brewfile.local: (none — full canonical Brewfile will apply)")
        fi
    else
        lines+=("repo root:    (not cloned)")
    fi

    if command -v bw >/dev/null 2>&1; then
        lines+=("Bitwarden CLI: $(bw --version)")
        local bw_state
        bw_state="$(bw status 2>/dev/null | grep -oE '"status":"[^"]+"' || true)"
        lines+=("  $bw_state")
    fi

    printf "%s\n" "${lines[@]}" | gum pager
}

view_dotfiles() {
    local repo_root
    repo_root="$(get_repo_root)"
    local dotfiles
    if [[ -n "$repo_root" ]]; then
        dotfiles="$(cd "$repo_root/chezmoi" 2>/dev/null && find . -type f -not -path '*/.chezmoiscripts/*' \( -name 'dot_*' -o -name 'private_dot_*' -o -path '*/dot_*' -o -path '*/private_dot_*' \) | sort)"
    else
        # Fallback: curl directory listing isn't available; tell user.
        dotfiles="(repo not cloned yet — run 'setup' first to see managed files)"
    fi
    printf "Managed dotfiles (chezmoi source paths):\n\n%s\n" "$dotfiles" | gum pager
}

view_hooks() {
    local repo_root
    repo_root="$(get_repo_root)"
    if [[ -z "$repo_root" ]]; then
        printf "Repo not cloned yet — run 'setup' first.\n" | gum pager
        return
    fi
    local files=("$repo_root"/chezmoi/.chezmoiscripts/*)
    local choice
    choice="$(printf "%s\n" "${files[@]}" | sed "s|$repo_root/chezmoi/.chezmoiscripts/||" | gum choose --header "Pick a hook to view:")"
    [[ -z "$choice" ]] && return
    gum pager < "$repo_root/chezmoi/.chezmoiscripts/$choice"
}

cmd_browse() {
    while true; do
        local choice
        choice="$(gum choose --header "Browse — read-only:" \
            "Canonical Brewfile" \
            "Current chezmoi state and active Brewfile" \
            "Managed dotfiles list" \
            "chezmoi script hooks" \
            "Usage guide (docs/usage.md)" \
            "Open GitHub repo in browser" \
            "Back to main menu")" || break
        case "$choice" in
            "Canonical Brewfile"*)              view_brewfile ;;
            "Current chezmoi state"*)           view_state ;;
            "Managed dotfiles"*)                view_dotfiles ;;
            "chezmoi script hooks"*)            view_hooks ;;
            "Usage guide"*)                     view_usage_doc ;;
            "Open GitHub"*)                     open "$REPO_URL" || ok "URL: $REPO_URL" ;;
            "Back"*|"")                         break ;;
        esac
    done
}

# ── Main ──

main() {
    preflight

    local subcommand="${1:-}"
    [[ $# -gt 0 ]] && shift   # remove subcommand from "$@" so the remainder
                              # can be forwarded to whichever cmd_* it picks

    # If user passed a direct subcommand, validate quickly and dispatch.
    case "$subcommand" in
        setup|update|sync|customize|add-key|scan-cli|scan-macos|scan-autostart|doctor|fork|browse|"")
            ;;
        --help|-h|help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            err "Unknown subcommand: $subcommand (try: setup, update, sync, customize, add-key, scan-cli, scan-macos, scan-autostart, doctor, fork, browse)"
            ;;
    esac

    # Always install minimum needed to render the gum menu.
    say "Bootstrapping Mac dotfiles ($REPO@$REPO_BRANCH)..."
    install_xcode_clt
    install_homebrew

    # If we already have gum, no need to install — saves seconds on warm machines.
    if ! command -v gum >/dev/null 2>&1; then
        install_bootstrap_deps gum
    fi

    if [[ -z "$subcommand" ]]; then
        local choice
        choice="$(show_main_menu)"
        subcommand="${choice%% *}"
        # Strip trailing whitespace just in case
        subcommand="${subcommand// /}"
    fi

    case "$subcommand" in
        setup)     cmd_setup ;;
        update)    cmd_update ;;
        sync)      install_bootstrap_deps gum bitwarden-cli yq jq; cmd_sync ;;
        customize) install_bootstrap_deps gum;                     cmd_customize ;;
        add-key)   install_bootstrap_deps gum bitwarden-cli jq;    cmd_add_key "$@" ;;
        scan-cli)  install_bootstrap_deps gum;                     cmd_scan_cli "$@" ;;
        scan-macos) install_bootstrap_deps gum;                    cmd_scan_macos "$@" ;;
        scan-autostart) install_bootstrap_deps gum;               cmd_scan_autostart "$@" ;;
        doctor)    install_bootstrap_deps gum;                     cmd_doctor "$@" ;;
        fork)      install_bootstrap_deps gum git;                 cmd_fork "$@" ;;
        browse)    cmd_browse ;;
        exit)      ok "Bye." ;;
        *)         err "Unknown choice: $subcommand" ;;
    esac
}

main "$@"
