#!/usr/bin/env bash
# Walk every directory in $PATH, list executables, and classify each by
# install source: brew formula, npm/pnpm global, cargo crate, system, …
# Surfaces "uncategorized" CLIs — typically curl-installed binaries or
# language-specific globals — that wouldn't reach a fresh Mac via
# Brewfile alone.
#
# Modes:
#   scan-cli.sh                  # categorized report (read-only)
#   scan-cli.sh --capture        # also write cli-globals.txt with the
#                                # npm/pnpm/cargo/go/pip globals
#   scan-cli.sh --uncategorized  # show only the uncategorized list
#
# Flags:
#   --capture           write cli-globals.txt (overwrites)
#   --uncategorized     show only uncategorized
#   --json              machine-readable output
#   --output <path>     change capture target (default: <repo>/cli-globals.txt)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="$REPO_ROOT/cli-globals.txt"
CAPTURE=0
ONLY_UNCAT=0
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --capture)        CAPTURE=1; shift ;;
        --uncategorized)  ONLY_UNCAT=1; shift ;;
        --json)           JSON_OUT=1; shift ;;
        --output)
            [[ -z "${2:-}" ]] && { echo "--output requires a path argument" >&2; exit 2; }
            OUTPUT="$2"; shift 2 ;;
        --help|-h)        sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

TMP="$(mktemp -d -t dotforge-cli.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Building classification index..." >&2

brew_prefix="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
go_bin_dir="${GOBIN:-${GOPATH:-$HOME/go}/bin}"

classify() {
    local path="$2"   # $1 is name (unused, kept for symmetry)
    case "$path" in
        /usr/bin/*|/bin/*|/sbin/*|/usr/sbin/*) echo "system"; return ;;
        /Library/Apple/usr/bin/*|/System/*)    echo "system"; return ;;
        /Library/Developer/CommandLineTools/usr/bin/*) echo "xcode"; return ;;
    esac
    # Brew arms come BEFORE the hardcoded /usr/local/bin fallback: on Intel
    # Macs brew_prefix == /usr/local, so a brew binary would otherwise be
    # misclassified as "thirdparty".
    case "$path" in
        "$brew_prefix"/Caskroom/*)  echo "cask"; return ;;
        "$brew_prefix"/Cellar/*|"$brew_prefix"/opt/*)
            echo "brew"; return ;;
        "$brew_prefix"/bin/*|"$brew_prefix"/sbin/*)
            echo "brew"; return ;;
    esac
    # /usr/local/bin on Apple Silicon is NOT brew (brew is /opt/homebrew).
    # CLIs here typically come from a cask's pkg installer (Docker, Tailscale)
    # or were installed by hand. Skipped on Intel where brew owns this prefix.
    if [[ "$brew_prefix" != "/usr/local" ]]; then
        case "$path" in
            /usr/local/bin/*|/usr/local/sbin/*) echo "thirdparty"; return ;;
        esac
    fi
    case "$path" in
        "$HOME"/.nvm/versions/node/*/bin/*)  echo "npm"; return ;;
        "$HOME"/Library/pnpm/*)              echo "pnpm"; return ;;
        "$HOME"/.cargo/bin/*)                echo "cargo"; return ;;
        "$go_bin_dir"/*)                     echo "go"; return ;;
        "$HOME"/.local/bin/*)                echo "pip"; return ;;
    esac
    if [[ -n "${PNPM_HOME:-}" ]]; then
        case "$path" in
            "$PNPM_HOME"/*)  echo "pnpm"; return ;;
        esac
    fi
    echo "uncategorized"
}

# ── Walk PATH (first hit wins, like the shell) ──

declare -a PATH_DIRS
IFS=':' read -ra PATH_DIRS <<< "$PATH"

results_file="$TMP/results.txt"
: > "$results_file"

# Bash 3.2 (macOS default) has no associative arrays — use a temp file as
# the seen-set so the script runs on a fresh Mac without brewed bash 5.
seen_file="$TMP/seen.txt"
: > "$seen_file"

for dir in "${PATH_DIRS[@]}"; do
    [[ -z "$dir" || ! -d "$dir" ]] && continue
    while IFS= read -r -d '' f; do
        local_name="$(basename "$f")"
        if grep -Fxq "$local_name" "$seen_file"; then
            continue
        fi
        printf "%s\n" "$local_name" >> "$seen_file"
        cat_label="$(classify "$local_name" "$f")"
        printf "%s\t%s\t%s\n" "$cat_label" "$local_name" "$f" >> "$results_file"
    done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) -perm -u+x -print0 2>/dev/null)
done

# ── Report ──

if (( JSON_OUT == 1 )); then
    awk -F'\t' 'BEGIN{print "["} {
        printf("%s{\"category\":\"%s\",\"name\":\"%s\",\"path\":\"%s\"}", (NR==1?"":","), $1, $2, $3)
    } END{print "\n]"}' "$results_file"
    exit 0
fi

if (( ONLY_UNCAT == 1 )); then
    echo ""
    echo "── Uncategorized binaries in PATH ──"
    awk -F'\t' '$1 == "uncategorized" { printf("  %-30s %s\n", $2, $3) }' "$results_file" \
        | sort | uniq
    exit 0
fi

echo ""
echo "── PATH scan summary ──"
awk -F'\t' '{c[$1]++} END { for (k in c) printf("  %-15s %d\n", k, c[k]) }' "$results_file" \
    | sort -k2 -n -r

echo ""
uncat_count="$(awk -F'\t' '$1 == "uncategorized"' "$results_file" | wc -l | tr -d ' ')"
if [[ "$uncat_count" == "0" ]]; then
    echo "── Uncategorized ──"
    echo "  ✓ Nothing uncategorized."
else
    echo "── Uncategorized (${uncat_count} entries — likely needs explicit tracking) ──"
    awk -F'\t' '$1 == "uncategorized" { printf("  %-30s %s\n", $2, $3) }' "$results_file" \
        | sort
fi

# ── Capture mode ──

if (( CAPTURE == 1 )); then
    echo ""
    if [[ -f "$OUTPUT" ]]; then
        cp "$OUTPUT" "${OUTPUT}.bak"
        echo "→ Backed up existing $OUTPUT to ${OUTPUT}.bak"
    fi
    echo "→ Capturing globals to $OUTPUT..."

    # Per-source stderr files; checked after each block so a non-zero exit
    # from npm/pnpm/cargo/pip surfaces instead of silently producing a
    # truncated cli-globals.txt.
    capture_err="$TMP/capture-err"
    mkdir -p "$capture_err"
    warn_if_failed() {
        local src="$1"
        local rc="$2"
        local errfile="$capture_err/$src.err"
        if (( rc != 0 )); then
            echo "  ⚠ $src list returned exit $rc — captured list may be incomplete" >&2
            [[ -s "$errfile" ]] && sed 's/^/    /' "$errfile" >&2
        fi
    }

    {
        printf "# Generated by scripts/scan-cli.sh on %s\n" "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf "# Format: <source>:<package>\n"
        printf "# Sources: npm, pnpm, cargo, go, pip\n"
        printf "# The chezmoi hook run_onchange_30-install-cli-globals.sh.tmpl\n"
        printf "# replays each line on a fresh machine after the matching\n"
        printf "# package manager is set up.\n"

        printf "\n# ── npm globals ──\n"
        if command -v npm >/dev/null 2>&1; then
            npm_rc=0
            { npm ls -g --depth=0 --parseable 2>"$capture_err/npm.err" \
                | awk -F'/node_modules/' 'NF>1{print "npm:"$NF}' \
                | sort -u; } || npm_rc=${PIPESTATUS[0]}
            warn_if_failed npm "$npm_rc"
        fi

        printf "\n# ── pnpm globals ──\n"
        if command -v pnpm >/dev/null 2>&1; then
            # Split on /node_modules/ (not /) so scoped names like
            # @nestjs/cli survive — otherwise $NF would drop the scope.
            pnpm_rc=0
            { pnpm list -g --depth=0 --parseable 2>"$capture_err/pnpm.err" \
                | awk -F'/node_modules/' 'NF>1{print "pnpm:"$NF}' \
                | sort -u; } || pnpm_rc=${PIPESTATUS[0]}
            warn_if_failed pnpm "$pnpm_rc"
        fi

        printf "\n# ── cargo crates ──\n"
        if command -v cargo >/dev/null 2>&1; then
            cargo_rc=0
            { cargo install --list 2>"$capture_err/cargo.err" \
                | awk '/^[a-zA-Z]/ {print "cargo:" $1}' \
                | sort -u; } || cargo_rc=${PIPESTATUS[0]}
            warn_if_failed cargo "$cargo_rc"
        fi

        printf "\n# ── go binaries ──\n"
        if [[ -d "$go_bin_dir" ]]; then
            find "$go_bin_dir" -maxdepth 1 -type f -perm -u+x -exec basename {} \; 2>/dev/null \
                | awk '{print "go:" $0}' | sort -u
        fi

        printf "\n# ── pip user packages ──\n"
        if command -v pip3 >/dev/null 2>&1; then
            pip_rc=0
            { pip3 list --user --format=freeze 2>"$capture_err/pip.err" \
                | awk -F'==' '{print "pip:" $1}' \
                | sort -u; } || pip_rc=${PIPESTATUS[0]}
            warn_if_failed pip "$pip_rc"
        fi
    } > "$OUTPUT"

    n_captured="$(grep -cE '^(npm|pnpm|cargo|go|pip):' "$OUTPUT" 2>/dev/null || true)"
    [[ -z "$n_captured" ]] && n_captured=0
    if [[ "$n_captured" -eq 0 ]]; then
        echo "  ⚠ No global packages captured — verify npm/pnpm/cargo/go/pip are on PATH (e.g. nvm loaded)." >&2
    fi
    echo "✓ Captured $n_captured global package(s)"
    echo ""
    echo "  Review:  cat $OUTPUT"
    echo "  Commit:  git -C $REPO_ROOT add cli-globals.txt"
fi
