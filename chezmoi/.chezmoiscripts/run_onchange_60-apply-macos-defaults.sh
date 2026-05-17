#!/usr/bin/env bash
# Apply macOS defaults read from $REPO_ROOT/chezmoi/dot_config/dotforge/macos-defaults.txt.
#
# Idempotent: `defaults write` overwrites the key with the same value on
# re-runs — no observable side effect.
#
# DRY_RUN support: set DRY_RUN=1 to print "would: <command>" for every
# defaults write without executing, and skip the killall at the end.
#
# NOTE: chezmoi re-runs this script when its content (sha) changes. After
# editing chezmoi/dot_config/dotforge/macos-defaults.txt, also touch this
# script (or update the comment version) to trigger re-application.
#   comment-version: 1
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
# Shadow the `defaults` binary so the loop can stay verbatim.
defaults() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo "would: defaults $*"
    else
        command defaults "$@"
        local rc=$?
        if (( rc != 0 )); then
            log_warn "defaults $* failed (exit $rc) — continuing"
        fi
    fi
}

log_info "Applying macOS defaults..."

# ── Screenshots directory (not in macos-defaults.txt) ──
if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "would: mkdir -p $HOME/Pictures/Screenshots"
else
    mkdir -p "$HOME/Pictures/Screenshots"
fi

# ── Read defaults from file ──
DEFAULTS_FILE="$REPO_ROOT/chezmoi/dot_config/dotforge/macos-defaults.txt"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    log_warn "macOS defaults file not found at $DEFAULTS_FILE — skipping (run 'dot snapshot' to create one)"
    exit 0
fi

count=0
while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue

    # Parse via read -ra (NOT eval — file is trusted but values could contain
    # shell metachars; eval would execute arbitrary code).
    read -ra tokens <<<"$line"

    # Sanity check: first token MUST be literal "defaults"
    if [[ "${tokens[0]:-}" != "defaults" ]]; then
        log_warn "skipping non-defaults line: $line"
        continue
    fi

    # Strip surrounding ASCII double-quotes from each token (read -ra keeps
    # them literal; defaults binary does not want them).
    for i in "${!tokens[@]}"; do
        t="${tokens[$i]}"
        [[ "$t" == \"*\" ]] && tokens[i]="${t:1:${#t}-2}"
    done

    # Call defaults binary directly with the remaining args — no shell
    # interpretation of values.
    defaults "${tokens[@]:1}"
    count=$((count + 1))
done < "$DEFAULTS_FILE"

# ── Restart affected services ──
if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "would: killall Dock Finder SystemUIServer"
else
    killall Dock Finder SystemUIServer 2>/dev/null || true
fi

log_ok "Applied $count macOS defaults from $DEFAULTS_FILE"
