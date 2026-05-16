#!/usr/bin/env bash
# scan-login-autostart — dump current Login Items + ~/Library/LaunchAgents
# for use as a baseline in login-items.txt / private_dot_Library/private_LaunchAgents.
#
# Usage:
#   scripts/scan-login-autostart.sh           # print current login items + LaunchAgents
#   scripts/scan-login-autostart.sh --diff    # compare login items against login-items.txt baseline
#   scripts/scan-login-autostart.sh --capture # capture current login items to login-items.txt

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh" 2>/dev/null || {
    # fallback no-op loggers if lib/log.sh missing (shouldn't happen in normal flow)
    log_info() { printf "%s\n" "$*"; }
    log_warn() { printf "WARN: %s\n" "$*" >&2; }
    log_error() { printf "ERROR: %s\n" "$*" >&2; }
}

DIFF_MODE=0
CAPTURE_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff)
            DIFF_MODE=1
            shift
            ;;
        --capture)
            CAPTURE_MODE=1
            shift
            ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf "Unknown argument: %s\n" "$1" >&2
            exit 2
            ;;
    esac
done

# ── Login Items ──

printf "\n# ── Login Items ──\n"
printf "# (paste into login-items.txt — one /Applications/Foo.app per line)\n"

raw_items=""
raw_items="$(osascript -e 'tell application "System Events" to get the path of every login item' 2>&1)"
osascript_rc=$?
if (( osascript_rc != 0 )); then
    if (( CAPTURE_MODE == 1 )); then
        log_error "osascript failed (exit $osascript_rc): $raw_items"
        log_error "if the error mentions Automation, grant access in System Settings → Privacy & Security → Automation, then re-run"
        exit 1
    fi
    log_warn "osascript failed (exit $osascript_rc): $raw_items"
    log_warn "if the error mentions Automation, grant access in System Settings → Privacy & Security → Automation, then re-run"
    current_items=()
else
    # osascript succeeded — may be empty if no login items
    # Strip all whitespace to detect the truly-empty case
    trimmed="${raw_items//[[:space:]]/}"
    if [[ -z "$trimmed" ]]; then
        # zero items
        current_items=()
    else
        # osascript returns comma-space-separated paths.
        # Paths can contain spaces (e.g. "DisplayLink Manager.app"), so we must
        # split ONLY on the literal ", " separator — not on every space.
        # Replace ", " with a newline, then read line-by-line (bash 3.2 safe).
        current_items=()
        while IFS= read -r item; do
            # Only include real paths (starting with /); osascript may return
            # "missing value" for stale entries whose app has been removed.
            [[ "$item" == /* ]] && current_items+=("$item")
        done < <(printf "%s" "$raw_items" | sed 's/, /\n/g')
    fi
fi

# ── Capture mode ──
if (( CAPTURE_MODE == 1 )); then
    OUTPUT="$REPO_ROOT/login-items.txt"

    # Backup existing file if present
    if [[ -f "$OUTPUT" ]]; then
        cp "$OUTPUT" "${OUTPUT}.bak"
        printf "→ Backed up existing %s to %s.bak\n" "$OUTPUT" "$OUTPUT"
    fi

    printf "→ Capturing login items to %s...\n" "$OUTPUT"

    # Sort the items lexicographically and write to file (LF endings)
    {
        if (( ${#current_items[@]} > 0 )); then
            printf "%s\n" "${current_items[@]}" | sort
        fi
    } > "$OUTPUT"

    printf "✓ Captured %d login item(s) to %s\n" "${#current_items[@]}" "$OUTPUT"
    exit 0
fi

if (( DIFF_MODE == 0 )); then
    if (( ${#current_items[@]} == 0 )); then
        printf "# (no login items currently set)\n"
    else
        for item in "${current_items[@]}"; do
            [[ -n "$item" ]] && printf "%s\n" "$item"
        done
    fi
else
    # --diff mode: compare against login-items.txt baseline
    baseline_file="$REPO_ROOT/login-items.txt"
    baseline_items=()
    if [[ -f "$baseline_file" ]]; then
        while IFS= read -r line; do
            # strip comments and blank lines
            line="${line%%#*}"
            # trim leading/trailing whitespace (bash 3.2 compatible)
            line="$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [[ -n "$line" ]] && baseline_items+=("$line")
        done < "$baseline_file"
    else
        log_warn "login-items.txt not found at $baseline_file — no baseline to compare against."
    fi

    # Items in current but NOT in baseline → would be added
    added=()
    if (( ${#current_items[@]} > 0 )); then
        for item in "${current_items[@]}"; do
            [[ -z "$item" ]] && continue
            found=0
            if (( ${#baseline_items[@]} > 0 )); then
                for b in "${baseline_items[@]}"; do
                    [[ "$item" == "$b" ]] && found=1 && break
                done
            fi
            (( found == 0 )) && added+=("$item")
        done
    fi

    # Items in baseline but NOT in current → no longer active
    removed=()
    if (( ${#baseline_items[@]} > 0 )); then
        for b in "${baseline_items[@]}"; do
            [[ -z "$b" ]] && continue
            found=0
            if (( ${#current_items[@]} > 0 )); then
                for item in "${current_items[@]}"; do
                    [[ "$b" == "$item" ]] && found=1 && break
                done
            fi
            (( found == 0 )) && removed+=("$b")
        done
    fi

    if (( ${#added[@]} == 0 && ${#removed[@]} == 0 )); then
        printf "# (login items match baseline)\n"
    else
        if (( ${#added[@]} > 0 )); then
            for item in "${added[@]}"; do
                printf "+ %s\n" "$item"
            done
        fi
        if (( ${#removed[@]} > 0 )); then
            for item in "${removed[@]}"; do
                printf "- %s\n" "$item"
            done
        fi
    fi
fi

# ── LaunchAgents ──
# Note: --diff mode is not applicable here (no versioned baseline for LaunchAgents).
# Both modes print the same LaunchAgents output.

printf "\n# ── LaunchAgents (~/Library/LaunchAgents) ──\n"
printf "# Human-readable survey — review and decide what to version.\n"

LA_DIR="$HOME/Library/LaunchAgents"

if [[ ! -d "$LA_DIR" ]]; then
    printf "# (~/Library/LaunchAgents does not exist — no user launch agents installed)\n"
else
    # Collect .plist files (bash 3.2 compatible glob expansion)
    plist_count=0
    for plist in "$LA_DIR"/*.plist; do
        # Skip if glob matched nothing (file literally named *.plist doesn't exist)
        [[ -e "$plist" ]] || continue

        filename="$(basename "$plist")"

        # Read Label (fallback to filename without .plist)
        label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null || true)"
        [[ -z "$label" ]] && label="${filename%.plist}"

        # Read first ProgramArguments entry; fallback to Program key
        program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)"
        if [[ -z "$program" ]]; then
            program="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null || true)"
        fi
        [[ -z "$program" ]] && program="(unknown)"

        # Guess source by Label prefix
        source_guess="custom (consider versioning)"
        case "$label" in
            com.docker.*)           source_guess="Docker (cask)" ;;
            com.backblaze.*)        source_guess="Backblaze (cask)" ;;
            pro.karabiner.*)        source_guess="Karabiner (cask)" ;;
            com.googlecode.iterm2.*) source_guess="iTerm2 (cask)" ;;
            com.apple.*)            source_guess="Apple system" ;;
            homebrew.*)             source_guess="Homebrew service" ;;
        esac

        printf "%s  [%s]  Label=%s  Program=%s\n" \
            "$filename" "$source_guess" "$label" "$program"

        plist_count=$(( plist_count + 1 ))
    done

    if (( plist_count == 0 )); then
        printf "# (no .plist files found in ~/Library/LaunchAgents)\n"
    fi
fi

printf "\n# To track a custom plist, copy it into the repo:\n"
printf "#   cp ~/Library/LaunchAgents/<file>.plist chezmoi/private_dot_Library/private_LaunchAgents/\n"
