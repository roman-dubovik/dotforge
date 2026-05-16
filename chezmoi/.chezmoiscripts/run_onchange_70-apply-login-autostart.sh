#!/usr/bin/env bash
# Apply login items (System Settings → General → Login Items) from login-items.txt
# Load custom LaunchAgents that chezmoi placed under ~/Library/LaunchAgents/
# version: login-autostart-v1
#
# Idempotent: re-running reports "already present" for existing login items;
# launchctl bootout + bootstrap is the standard reload pattern.
#
# DRY_RUN support: set DRY_RUN=1 to print "would: <command>" without executing.
#
# Usage (chezmoi runs this automatically on change):
#   chezmoi apply
# Manual:
#   bash chezmoi/.chezmoiscripts/run_onchange_70-apply-login-autostart.sh
#   DRY_RUN=1 bash chezmoi/.chezmoiscripts/run_onchange_70-apply-login-autostart.sh

set -uo pipefail

SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
REPO_ROOT="${SOURCE_PATH%/chezmoi}"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/log.sh"

LOGIN_ITEMS_FILE="$REPO_ROOT/login-items.txt"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"

# ── DRY_RUN helper ──
run_or_dry() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo "would: $*"
        return 0
    fi
    "$@"
}

# ── Counters (all pre-declared to satisfy set -u) ──
applied=0
already_present=0
missing=0
failed=0
loaded=0
warnings=0

# ════════════════════════════════════════════════════
# Login Items section
# ════════════════════════════════════════════════════
log_info "Applying login items from login-items.txt..."

if [[ ! -f "$LOGIN_ITEMS_FILE" ]]; then
    log_warn "login-items.txt not found at $LOGIN_ITEMS_FILE — skipping login items"
    (( warnings++ )) || true
else
    # Fetch existing login items once. Guard against Automation permission denial.
    existing_items=""
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        existing_items="(dry-run)"
    else
        existing_items="$(osascript -e 'tell application "System Events" to get the path of every login item' 2>&1)"
        osa_rc=$?
        if (( osa_rc != 0 )); then
            log_warn "osascript could not list login items (exit $osa_rc): $existing_items"
            log_warn "Grant Automation access in System Settings → Privacy & Security → Automation, then re-run."
            log_warn "Skipping login items section."
            existing_items=""
            (( warnings++ )) || true
            # Signal that we should skip all further login item processing
            LOGIN_ITEMS_BLOCKED=1
        fi
    fi
    LOGIN_ITEMS_BLOCKED="${LOGIN_ITEMS_BLOCKED:-0}"

    if [[ "$LOGIN_ITEMS_BLOCKED" == "0" ]]; then
        # Wrap the list with leading/trailing comma+space for exact-match anchoring
        # (avoids matching /Applications/Foo.app inside /Applications/Foo.app.bak)
        anchored_list=", ${existing_items}, "

        while IFS= read -r line; do
            # Skip blank lines and comments
            [[ -z "$line" || "$line" == \#* ]] && continue

            path="$line"

            # App not installed on this machine
            if [[ ! -e "$path" ]]; then
                log_warn "app not installed, skipping: $path"
                (( missing++ )) || true
                (( warnings++ )) || true
                continue
            fi

            if [[ "${DRY_RUN:-0}" == "1" ]]; then
                # In dry-run we can't query real state — report as would-apply
                run_or_dry osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$path\", hidden:false}"
                (( applied++ )) || true
                continue
            fi

            # Exact-match check: search for ", <path>, " in the anchored list
            if [[ "$anchored_list" == *", $path, "* ]]; then
                log_ok "$path already a login item"
                (( already_present++ )) || true
                continue
            fi

            # Add the login item
            add_out="$(osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$path\", hidden:false}" 2>&1)"
            add_rc=$?
            if (( add_rc != 0 )); then
                log_warn "failed to add login item: $path (exit $add_rc): $add_out"
                log_warn "Grant Automation access in System Settings → Privacy & Security → Automation, then re-run."
                (( failed++ )) || true
                (( warnings++ )) || true
            else
                log_ok "Added login item: $path"
                (( applied++ )) || true
            fi

        done < "$LOGIN_ITEMS_FILE"
    fi
fi

# ════════════════════════════════════════════════════
# LaunchAgents section
# ════════════════════════════════════════════════════
log_info "Loading custom LaunchAgents from $LAUNCHAGENTS_DIR..."

# nullglob: empty glob expands to nothing instead of literal "*.plist"
shopt -s nullglob

for plist in "$LAUNCHAGENTS_DIR"/*.plist; do
    # Extract the Label from the plist
    label=""
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null)"
    if [[ -z "$label" ]]; then
        log_warn "No Label found in $plist — skipping"
        (( warnings++ )) || true
        continue
    fi

    # bootout first (ignore "service not loaded" errors) to allow clean reload
    run_or_dry launchctl bootout "gui/$UID/$label" 2>/dev/null || true

    # bootstrap
    if run_or_dry launchctl bootstrap "gui/$UID" "$plist"; then
        log_ok "Loaded LaunchAgent: $label ($plist)"
        (( loaded++ )) || true
    else
        boot_rc=$?
        log_warn "Failed to load LaunchAgent: $plist (exit $boot_rc)"
        (( warnings++ )) || true
    fi
done

shopt -u nullglob

# ════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════
log_ok "Login autostart: $applied login items applied ($already_present already present, $missing missing, $failed failed); $loaded launch agents loaded ($warnings warnings)"
