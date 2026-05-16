#!/usr/bin/env bash
# dotforge doctor — unified read-only diagnostic.
#
# Usage:
#   scripts/doctor.sh              # run all 8 checks
#   scripts/doctor.sh --check=<name>   # run a single named check
#   scripts/doctor.sh --color     # force ANSI colour output
#   scripts/doctor.sh --no-color  # force plain text
#
# Named checks (--check=<name>):
#   chezmoi, brewfile, cli-globals, curl-toolchains,
#   ssh-keys, macos-defaults, login-autostart, repo
#
# Exit codes:
#   0  all checks OK
#   1  ≥1 WARN, 0 FAIL
#   2  ≥1 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Option parsing ──

COLOR_MODE="auto"   # auto | on | off
SINGLE_CHECK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --color)      COLOR_MODE="on";  shift ;;
        --no-color)   COLOR_MODE="off"; shift ;;
        --check=*)    SINGLE_CHECK="${1#--check=}"; shift ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)  printf "Unknown argument: %s\n" "$1" >&2; exit 2 ;;
    esac
done

# ── Color setup (independent of lib/log.sh to avoid readonly conflicts) ──
# Doctor defines its own colour variables post-arg-parse.

if [[ "$COLOR_MODE" == "on" ]] || { [[ "$COLOR_MODE" == "auto" ]] && [[ -t 1 ]]; }; then
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_RESET=$'\033[0m'
else
    C_GREEN="" C_YELLOW="" C_RED="" C_RESET=""
fi

# ── Status counters ──

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# ── Status printer ──
# print_status <STATUS> <label> <details>
# STATUS must be OK | WARN | FAIL
# Label is right-padded to 22 chars; bracket prefix is right-padded to 6 chars.
print_status() {
    local status="$1"
    local label="$2"
    local details="$3"

    local color=""
    case "$status" in
        OK)   color="$C_GREEN";  OK_COUNT=$(( OK_COUNT + 1 ))   ;;
        WARN) color="$C_YELLOW"; WARN_COUNT=$(( WARN_COUNT + 1 )) ;;
        FAIL) color="$C_RED";    FAIL_COUNT=$(( FAIL_COUNT + 1 )) ;;
    esac

    printf "%s%-6s%s %-22s %s\n" \
        "$color" "[$status]" "$C_RESET" "$label" "$details"
}

# ── Check 1: chezmoi state ──

check_chezmoi() {
    # Prefer the user config location chezmoi reads
    local cfg1="$HOME/.config/chezmoi/chezmoi.toml"
    local cfg2="$HOME/.config/chezmoi/chezmoi.yaml"
    local cfg3="$HOME/.config/chezmoi/chezmoi.json"

    if ! command -v chezmoi >/dev/null 2>&1; then
        print_status FAIL "chezmoi state" "chezmoi not on PATH, run 'bootstrap.sh setup'"
        return
    fi

    if [[ ! -f "$cfg1" && ! -f "$cfg2" && ! -f "$cfg3" ]]; then
        print_status FAIL "chezmoi state" "chezmoi not initialized, run 'bootstrap.sh setup'"
        return
    fi

    local diff_out
    diff_out="$(chezmoi diff 2>&1)" || true
    if [[ -z "$diff_out" ]]; then
        print_status OK "chezmoi state" "no pending changes"
    else
        local n_files
        n_files="$(printf "%s\n" "$diff_out" | grep -c "^diff --git" || true)"
        print_status WARN "chezmoi state" "${n_files} file(s) would change on apply"
    fi
}

# ── Check 2: Brewfile divergence ──

check_brewfile() {
    if ! command -v brew >/dev/null 2>&1; then
        print_status WARN "Brewfile" "brew not on PATH — skip"
        return
    fi

    local brewfile
    if [[ -f "$REPO_ROOT/Brewfile.local" ]]; then
        brewfile="$REPO_ROOT/Brewfile.local"
    elif [[ -f "$REPO_ROOT/Brewfile" ]]; then
        brewfile="$REPO_ROOT/Brewfile"
    else
        print_status WARN "Brewfile" "no Brewfile found in repo"
        return
    fi

    local verbose_out rc
    verbose_out="$(brew bundle check --no-upgrade --verbose --file="$brewfile" 2>&1)" || rc=$?
    rc="${rc:-0}"

    if [[ "$rc" -eq 0 ]]; then
        print_status OK "Brewfile" "all packages satisfied"
    else
        # Lines like "→ Formula/Cask X needs to be installed."
        local missing
        missing="$(printf "%s\n" "$verbose_out" | grep -c "^→ " || true)"
        # Collect up to 3 names for details
        local names
        names="$(printf "%s\n" "$verbose_out" \
            | grep "^→ " \
            | sed 's/^→ [A-Za-z]* //' \
            | sed 's/ needs to be installed\.//' \
            | head -3 \
            | tr '\n' ',' \
            | sed 's/,$//')"
        if [[ "$missing" -gt 3 ]]; then
            names="${names}, …"
        fi
        print_status WARN "Brewfile" "missing ${missing} package(s): ${names}"
    fi
}

# ── Check 3: CLI globals replayed ──

check_cli_globals() {
    local globals_file="$REPO_ROOT/cli-globals.txt"

    if [[ ! -f "$globals_file" ]]; then
        print_status WARN "CLI globals" "cli-globals.txt missing, run 'bootstrap.sh scan-cli --capture' first"
        return
    fi

    # Source nvm so npm is available (mirrors the install hook)
    export NVM_DIR="$HOME/.nvm"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # set +u: nvm.sh references unset vars internally
        set +u
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
        nvm use default >/dev/null 2>&1 || true
        set -u
    fi

    # pnpm path
    local pnpm_home="$HOME/Library/pnpm"
    case ":${PATH}:" in
        *":${pnpm_home}:"*) ;;
        *) export PATH="${pnpm_home}:${PATH}" ;;
    esac
    local pnpm_home2="$HOME/.local/share/pnpm"
    case ":${PATH}:" in
        *":${pnpm_home2}:"*) ;;
        *) export PATH="${pnpm_home2}:${PATH}" ;;
    esac

    local total=0
    local missing=0
    local missing_managers=""

    while IFS= read -r line; do
        # Skip comments and blank lines
        case "$line" in
            \#*|"") continue ;;
        esac

        local src pkg
        src="${line%%:*}"
        pkg="${line#*:}"
        [[ -z "$pkg" || "$src" == "$pkg" ]] && continue

        total=$(( total + 1 ))

        case "$src" in
            npm)
                if ! command -v npm >/dev/null 2>&1; then
                    missing=$(( missing + 1 ))
                    case "$missing_managers" in
                        *npm*) ;;
                        *) missing_managers="${missing_managers:+$missing_managers, }npm" ;;
                    esac
                    continue
                fi
                if ! npm ls -g --depth=0 --parseable 2>/dev/null | grep -qE "/${pkg}(@|$)"; then
                    missing=$(( missing + 1 ))
                fi
                ;;
            pnpm)
                if ! command -v pnpm >/dev/null 2>&1; then
                    missing=$(( missing + 1 ))
                    case "$missing_managers" in
                        *pnpm*) ;;
                        *) missing_managers="${missing_managers:+$missing_managers, }pnpm" ;;
                    esac
                    continue
                fi
                if ! pnpm list -g --depth=0 --parseable 2>/dev/null | grep -qE "/${pkg}(@|$)"; then
                    missing=$(( missing + 1 ))
                fi
                ;;
            cargo)
                if ! command -v cargo >/dev/null 2>&1; then
                    missing=$(( missing + 1 ))
                    case "$missing_managers" in
                        *cargo*) ;;
                        *) missing_managers="${missing_managers:+$missing_managers, }cargo" ;;
                    esac
                    continue
                fi
                if ! cargo install --list 2>/dev/null | grep -qE "^${pkg} "; then
                    missing=$(( missing + 1 ))
                fi
                ;;
            go)
                if ! command -v go >/dev/null 2>&1; then
                    missing=$(( missing + 1 ))
                    case "$missing_managers" in
                        *"go "*|"go") ;;
                        *) missing_managers="${missing_managers:+$missing_managers, }go" ;;
                    esac
                    continue
                fi
                # Go binaries land in $GOPATH/bin or $HOME/go/bin
                local gobin="${GOPATH:-$HOME/go}/bin"
                if [[ ! -x "$gobin/$pkg" ]]; then
                    missing=$(( missing + 1 ))
                fi
                ;;
            pip)
                if ! command -v pip3 >/dev/null 2>&1; then
                    missing=$(( missing + 1 ))
                    case "$missing_managers" in
                        *pip*) ;;
                        *) missing_managers="${missing_managers:+$missing_managers, }pip3" ;;
                    esac
                    continue
                fi
                if ! pip3 list --user --format=freeze 2>/dev/null | grep -qiE "^${pkg}=="; then
                    missing=$(( missing + 1 ))
                fi
                ;;
            *)
                # Unknown source — treat as missing
                missing=$(( missing + 1 ))
                ;;
        esac
    done < "$globals_file"

    local present=$(( total - missing ))

    if [[ "$total" -eq 0 ]]; then
        print_status OK "CLI globals" "cli-globals.txt has no entries"
    elif [[ "$missing" -eq 0 ]]; then
        print_status OK "CLI globals" "${present}/${total} packages present"
    else
        local detail="${missing} missing (${present}/${total} present)"
        if [[ -n "$missing_managers" ]]; then
            detail="${detail}; managers not on PATH: ${missing_managers}"
        fi
        print_status WARN "CLI globals" "$detail"
    fi
}

# ── Check 4: Curl-based toolchains ──

check_curl_toolchains() {
    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    local -a items=(
        "oh-my-zsh|$HOME/.oh-my-zsh/oh-my-zsh.sh"
        "powerlevel10k|${zsh_custom}/themes/powerlevel10k"
        "zsh-syntax-highlighting|${zsh_custom}/plugins/zsh-syntax-highlighting"
        "zsh-autosuggestions|${zsh_custom}/plugins/zsh-autosuggestions"
        "zsh-completions|${zsh_custom}/plugins/zsh-completions"
        "nvm|$HOME/.nvm/nvm.sh"
        "pnpm|$HOME/Library/pnpm/pnpm OR $HOME/.local/share/pnpm/pnpm"
        "maestro|$HOME/.maestro/bin/maestro"
    )

    local total="${#items[@]}"
    local missing=0
    local missing_names=""

    local entry name path_spec
    for entry in "${items[@]}"; do
        name="${entry%%|*}"
        path_spec="${entry#*|}"

        local found=0
        # pnpm has two valid locations
        if [[ "$name" == "pnpm" ]]; then
            if [[ -x "$HOME/Library/pnpm/pnpm" || -x "$HOME/.local/share/pnpm/pnpm" ]]; then
                found=1
            fi
        else
            if [[ -e "$path_spec" ]]; then
                found=1
            fi
        fi

        if [[ "$found" -eq 0 ]]; then
            missing=$(( missing + 1 ))
            missing_names="${missing_names:+$missing_names, }${name}"
        fi
    done

    local present=$(( total - missing ))

    if [[ "$missing" -eq 0 ]]; then
        print_status OK "Curl-toolchains" "${present}/${total} installed"
    else
        print_status WARN "Curl-toolchains" "${missing} missing: ${missing_names}"
    fi
}

# ── Check 5: SSH keys present ──
# Non-interactively: glob ~/.ssh/ for dotforge-managed key files.
# We look for private key files (no extension) that appear alongside a .pub.
# If vault is locked or bw is absent we cannot enumerate expected keys —
# so we report what's on disk.  A count of 0 identity files → WARN.

check_ssh_keys() {
    local ssh_dir="$HOME/.ssh"

    if [[ ! -d "$ssh_dir" ]]; then
        print_status WARN "SSH keys" "$HOME/.ssh directory does not exist"
        return
    fi

    # Count identity files: files that have a matching .pub sibling.
    local count=0
    local key
    for key in "$ssh_dir"/*.pub; do
        [[ -e "$key" ]] || continue
        local priv="${key%.pub}"
        [[ -f "$priv" ]] && count=$(( count + 1 ))
    done

    if [[ "$count" -eq 0 ]]; then
        print_status WARN "SSH keys" "no SSH key pairs found in ~/.ssh"
    else
        print_status OK "SSH keys" "${count} key pair(s) present in ~/.ssh"
    fi
}

# ── Check 6: macOS defaults divergence ──

check_macos_defaults() {
    local scan_script="$REPO_ROOT/scripts/scan-macos-defaults.sh"

    if [[ ! -x "$scan_script" ]]; then
        print_status WARN "macOS defaults" "scan-macos-defaults.sh not found or not executable"
        return
    fi

    local diff_out
    diff_out="$(bash "$scan_script" --diff 2>&1)" || true

    # Count lines that represent actual divergence:
    #  - "defaults write ..."  = key has a different value than baseline
    #  - "# <domain> <key>: (not set" = key absent from system (also divergent)
    local n_write n_notset divergent
    n_write="$(printf "%s\n" "$diff_out" | grep -c "^defaults write" || true)"
    n_notset="$(printf "%s\n" "$diff_out" | grep -c "(not set" || true)"
    divergent=$(( n_write + n_notset ))

    if [[ "$divergent" -eq 0 ]]; then
        print_status OK "macOS defaults" "all keys match baseline"
    else
        print_status WARN "macOS defaults" "${divergent} key(s) diverge from baseline (run scan-macos --diff)"
    fi
}

# ── Check 7: Login items + LaunchAgents divergence ──

check_login_autostart() {
    local scan_script="$REPO_ROOT/scripts/scan-login-autostart.sh"

    if [[ ! -x "$scan_script" ]]; then
        print_status WARN "Login items" "scan-login-autostart.sh not found"
        return
    fi

    local diff_out
    diff_out="$(bash "$scan_script" --diff 2>&1)" || true

    # In --diff mode, lines starting with "+ " or "- " indicate drift.
    # LaunchAgents block always prints but has no +/- lines in --diff mode.
    local drift
    drift="$(printf "%s\n" "$diff_out" | grep -c "^[+-] " || true)"

    # Count chezmoi-managed LaunchAgents (those tracked in the repo)
    local la_dir="$REPO_ROOT/chezmoi/private_dot_Library/private_LaunchAgents"
    local managed_la=0
    if [[ -d "$la_dir" ]]; then
        for f in "$la_dir"/*.plist; do
            [[ -e "$f" ]] && managed_la=$(( managed_la + 1 ))
        done
    fi

    if [[ "$drift" -eq 0 ]]; then
        if [[ "$managed_la" -eq 0 ]]; then
            print_status OK "Login items" "matches baseline; 0 chezmoi-managed LaunchAgents"
        else
            print_status OK "Login items" "matches baseline; ${managed_la} chezmoi-managed LaunchAgent(s)"
        fi
    else
        print_status WARN "Login items" "${drift} login item(s) differ from baseline"
    fi
}

# ── Check 8: Git repo sync ──

check_repo_sync() {
    if ! command -v chezmoi >/dev/null 2>&1; then
        print_status WARN "Repo" "chezmoi not available — skip"
        return
    fi

    # Try to fetch from origin (requires network)
    local fetch_rc
    chezmoi git -- fetch origin >/dev/null 2>&1 || fetch_rc=$?
    fetch_rc="${fetch_rc:-0}"

    if [[ "$fetch_rc" -ne 0 ]]; then
        print_status WARN "Repo" "could not fetch origin (offline? git error)"
        return
    fi

    # Count commits local is behind origin/main
    local behind
    behind="$(chezmoi git -- rev-list --count HEAD..origin/main 2>/dev/null)" || behind=""

    if [[ -z "$behind" ]]; then
        print_status WARN "Repo" "could not determine sync status (upstream not set?)"
        return
    fi

    if [[ "$behind" -eq 0 ]]; then
        print_status OK "Repo" "up to date with origin/main"
    else
        print_status WARN "Repo" "${behind} commit(s) behind origin/main (run 'chezmoi update')"
    fi
}

# ── Dispatcher ──

run_check() {
    local name="$1"
    case "$name" in
        chezmoi)         check_chezmoi ;;
        brewfile)        check_brewfile ;;
        cli-globals)     check_cli_globals ;;
        curl-toolchains) check_curl_toolchains ;;
        ssh-keys)        check_ssh_keys ;;
        macos-defaults)  check_macos_defaults ;;
        login-autostart) check_login_autostart ;;
        repo)            check_repo_sync ;;
        *)
            printf "Unknown check name: %s\n" "$name" >&2
            printf "Valid names: chezmoi, brewfile, cli-globals, curl-toolchains, ssh-keys, macos-defaults, login-autostart, repo\n" >&2
            exit 2
            ;;
    esac
}

# ── Main ──

if [[ -n "$SINGLE_CHECK" ]]; then
    run_check "$SINGLE_CHECK"
else
    printf "dotforge doctor — %s\n\n" "$(date +%Y-%m-%dT%H:%M)"
    run_check chezmoi
    run_check brewfile
    run_check cli-globals
    run_check curl-toolchains
    run_check ssh-keys
    run_check macos-defaults
    run_check login-autostart
    run_check repo
    printf "\nSummary: %d OK, %d WARN, %d FAIL\n" \
        "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
fi

# Exit code: 2 if any FAIL, 1 if any WARN, 0 if all OK
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 2
elif [[ "$WARN_COUNT" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
