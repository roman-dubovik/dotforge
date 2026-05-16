#!/usr/bin/env bash
# Apply sensible macOS defaults for Dock, Finder, Screenshots, Keyboard,
# Trackpad, UI, and Safari.
#
# Idempotent: `defaults write` overwrites the key with the same value on
# re-runs — no observable side effect.
#
# DRY_RUN support: set DRY_RUN=1 to print "would: <command>" for every
# defaults write without executing, and skip the killall at the end.
#
# Usage (chezmoi runs this automatically on change):
#   chezmoi apply
# Manual:
#   bash chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh
#   DRY_RUN=1 bash chezmoi/.chezmoiscripts/run_onchange_60-apply-macos-defaults.sh

set -uo pipefail

SOURCE_PATH="$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
REPO_ROOT="${SOURCE_PATH%/chezmoi}"

# shellcheck source=/dev/null
. "$REPO_ROOT/lib/log.sh"

# ── DRY_RUN shim ──
# Shadow the `defaults` binary so the write block can stay verbatim.
defaults() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        echo "would: defaults $*"
    else
        command defaults "$@"
    fi
}

log_info "Applying macOS defaults..."

# ── Dock ──
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.2
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock minimize-to-application -bool true

# ── Finder ──
defaults write -g AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"   # list view
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder WarnOnEmptyTrash -bool false
defaults write NSGlobalDomain AppleShowAllFiles -bool true
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true   # no .DS_Store on network shares

# ── Screenshots ──
if [[ -n "${DRY_RUN:-}" ]]; then
    echo "would: mkdir -p $HOME/Pictures/Screenshots"
else
    mkdir -p "$HOME/Pictures/Screenshots"
fi
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture include-date -bool true

# ── Keyboard ──
defaults write -g KeyRepeat -int 2
defaults write -g InitialKeyRepeat -int 15
defaults write -g ApplePressAndHoldEnabled -bool false   # repeat instead of accent menu
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false

# ── Trackpad ──
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write -g com.apple.mouse.tapBehavior -int 1
defaults write -g com.apple.trackpad.scaling -float 1.5

# ── UI ──
defaults write -g NSWindowResizeTime -float 0.001
defaults write -g NSScrollAnimationEnabled -bool false
defaults write -g NSWindowShouldDragOnGesture -bool true
defaults write com.apple.LaunchServices LSQuarantine -bool false   # no "are you sure you want to open?"

# ── Safari (dev-friendly) ──
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true

# ── Restart affected services ──
if [[ -n "${DRY_RUN:-}" ]]; then
    echo "would: killall Dock Finder SystemUIServer"
else
    killall Dock Finder SystemUIServer 2>/dev/null || true
fi

log_ok "macOS defaults applied (35 keys across Dock, Finder, Screenshots, Keyboard, Trackpad, UI, Safari)"
