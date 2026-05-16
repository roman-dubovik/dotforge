#!/usr/bin/env bash
# Read current macOS defaults for all keys managed by the
# run_onchange_60-apply-macos-defaults.sh hook and print them as
# ready-to-paste `defaults write` commands.
#
# Usage:
#   scripts/scan-macos-defaults.sh           # print all keys (current values)
#   scripts/scan-macos-defaults.sh --diff    # print only keys that diverge from baseline
#
# Output format:
#   # ── <Section> ──
#   defaults write <domain> <key> -<type> <current-value>
#   # <domain> <key>: (not set)   ← when key is absent
#
# Type mapping from `defaults read-type` output:
#   Type is boolean  → -bool  (value: 0→false, 1→true)
#   Type is integer  → -int
#   Type is float    → -float
#   Type is string   → -string (value is quoted)
#
# Diff baseline is hardcoded to match the hook exactly.  To update the
# baseline, edit the BASELINE array below whenever the hook changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$REPO_ROOT/lib/log.sh"

# ── Option parsing ──
DIFF_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff)   DIFF_MODE=1; shift ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)  printf "Unknown argument: %s\n" "$1" >&2; exit 2 ;;
    esac
done

# ── Baseline table ──
# Format: <section>|<domain>|<key>|<type>|<baseline-value>
# domain "-g" means NSGlobalDomain (same as `defaults write -g`).
# Types: bool, int, float, string
# This table must stay in sync with the hook.
BASELINE=(
    # Dock
    "Dock|com.apple.dock|autohide|bool|true"
    "Dock|com.apple.dock|autohide-delay|float|0"
    "Dock|com.apple.dock|autohide-time-modifier|float|0.2"
    "Dock|com.apple.dock|tilesize|int|48"
    "Dock|com.apple.dock|show-recents|bool|false"
    "Dock|com.apple.dock|mineffect|string|scale"
    "Dock|com.apple.dock|minimize-to-application|bool|true"
    # Finder
    "Finder|-g|AppleShowAllExtensions|bool|true"
    "Finder|com.apple.finder|AppleShowAllFiles|bool|true"
    "Finder|com.apple.finder|ShowPathbar|bool|true"
    "Finder|com.apple.finder|ShowStatusBar|bool|true"
    "Finder|com.apple.finder|FXPreferredViewStyle|string|Nlsv"
    "Finder|com.apple.finder|_FXShowPosixPathInTitle|bool|true"
    "Finder|com.apple.finder|FXDefaultSearchScope|string|SCcf"
    "Finder|com.apple.finder|FXEnableExtensionChangeWarning|bool|false"
    "Finder|com.apple.finder|WarnOnEmptyTrash|bool|false"
    "Finder|NSGlobalDomain|AppleShowAllFiles|bool|true"
    "Finder|com.apple.desktopservices|DSDontWriteNetworkStores|bool|true"
    # Screenshots
    "Screenshots|com.apple.screencapture|location|string|$HOME/Pictures/Screenshots"
    "Screenshots|com.apple.screencapture|disable-shadow|bool|true"
    "Screenshots|com.apple.screencapture|type|string|png"
    "Screenshots|com.apple.screencapture|include-date|bool|true"
    # Keyboard
    "Keyboard|-g|KeyRepeat|int|2"
    "Keyboard|-g|InitialKeyRepeat|int|15"
    "Keyboard|-g|ApplePressAndHoldEnabled|bool|false"
    "Keyboard|-g|NSAutomaticSpellingCorrectionEnabled|bool|false"
    "Keyboard|-g|NSAutomaticCapitalizationEnabled|bool|false"
    "Keyboard|-g|NSAutomaticPeriodSubstitutionEnabled|bool|false"
    "Keyboard|-g|NSAutomaticDashSubstitutionEnabled|bool|false"
    "Keyboard|-g|NSAutomaticQuoteSubstitutionEnabled|bool|false"
    # Trackpad
    "Trackpad|com.apple.AppleMultitouchTrackpad|Clicking|bool|true"
    "Trackpad|com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|true"
    "Trackpad|-g|com.apple.mouse.tapBehavior|int|1"
    "Trackpad|-g|com.apple.trackpad.scaling|float|1.5"
    # UI
    "UI|-g|NSWindowResizeTime|float|0.001"
    "UI|-g|NSScrollAnimationEnabled|bool|false"
    "UI|-g|NSWindowShouldDragOnGesture|bool|true"
    "UI|com.apple.LaunchServices|LSQuarantine|bool|false"
    # Safari
    "Safari|com.apple.Safari|IncludeDevelopMenu|bool|true"
    "Safari|com.apple.Safari|WebKitDeveloperExtrasEnabledPreferenceKey|bool|true"
    "Safari|com.apple.Safari|com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled|bool|true"
)

# ── Helpers ──

# read_value <domain> <key>
# Prints the raw value from defaults, or empty string if not set.
read_value() {
    local domain="$1" key="$2"
    command defaults read "$domain" "$key" 2>/dev/null || true
}

# read_type <domain> <key>
# Prints one of: bool, int, float, string, other, notset
read_type() {
    local domain="$1" key="$2"
    local raw
    raw="$(command defaults read-type "$domain" "$key" 2>/dev/null)" || { echo "notset"; return; }
    case "$raw" in
        *boolean*) echo "bool" ;;
        *integer*) echo "int"  ;;
        *float*)   echo "float" ;;
        *string*)  echo "string" ;;
        *)         echo "other" ;;
    esac
}

# format_value <type> <raw-value>
# Converts raw defaults read output to a write-ready form.
format_value() {
    local type="$1" val="$2"
    case "$type" in
        bool)
            # defaults read returns 0 or 1 for booleans
            if [[ "$val" == "1" ]]; then echo "true"; else echo "false"; fi
            ;;
        string)
            # Quote strings for output
            printf '"%s"' "$val"
            ;;
        *)
            echo "$val"
            ;;
    esac
}

# values_equal <type> <current-raw> <baseline>
# Returns 0 if equal, 1 if different.
values_equal() {
    local type="$1" current="$2" baseline="$3"
    local normalized_current
    case "$type" in
        bool)
            if [[ "$current" == "1" ]]; then normalized_current="true"; else normalized_current="false"; fi
            ;;
        float)
            # Normalize: strip trailing zeros so 0 == 0.0 == 0.000
            normalized_current="$(printf "%g" "$current" 2>/dev/null || echo "$current")"
            ;;
        *)
            normalized_current="$current"
            ;;
    esac
    [[ "$normalized_current" == "$baseline" ]]
}

# ── Main scan ──

current_section=""
printed_header=0

for entry in "${BASELINE[@]}"; do
    # Skip comment lines (bash array entries starting with #)
    case "$entry" in
        \#*) continue ;;
    esac

    # Parse the pipe-separated entry
    IFS='|' read -r section domain key type baseline_val <<< "$entry"

    # Section header
    if [[ "$section" != "$current_section" ]]; then
        current_section="$section"
        if (( DIFF_MODE == 0 )); then
            printf "\n# ── %s ──\n" "$section"
        fi
        printed_header=0
    fi

    # Read current value
    current_raw="$(read_value "$domain" "$key")"

    if [[ -z "$current_raw" ]]; then
        # Key not set
        if (( DIFF_MODE == 0 )); then
            printf "# %s %s: (not set)\n" "$domain" "$key"
        else
            # In diff mode: not-set counts as divergent (baseline would set it)
            if (( printed_header == 0 )); then
                printf "\n# ── %s ──\n" "$section"
                printed_header=1
            fi
            printf "# %s %s: (not set — baseline: %s)\n" "$domain" "$key" "$baseline_val"
        fi
        continue
    fi

    # Format the current value for output
    formatted="$(format_value "$type" "$current_raw")"

    if (( DIFF_MODE == 1 )); then
        # Only print if divergent from baseline
        if ! values_equal "$type" "$current_raw" "$baseline_val"; then
            if (( printed_header == 0 )); then
                printf "\n# ── %s ──\n" "$section"
                printed_header=1
            fi
            printf "defaults write %s %s -%s %s\n" "$domain" "$key" "$type" "$formatted"
        fi
    else
        printf "defaults write %s %s -%s %s\n" "$domain" "$key" "$type" "$formatted"
    fi
done

if (( DIFF_MODE == 1 )); then
    printf "\n# (keys matching baseline are omitted)\n"
fi
