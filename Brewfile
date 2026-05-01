# ── Taps ──
tap "hudochenkov/sshpass"
tap "ngrok/ngrok"
tap "supabase/tap"

# ── CLI essentials ──
brew "git"
brew "zsh"
brew "curl"
brew "wget"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "bat"
brew "eza"
brew "tree"
brew "tmux"
brew "gh"            # GitHub CLI
brew "lazygit"
brew "gnu-sed"
brew "mas"           # Mac App Store CLI (used below)
brew "parallel"
brew "pv"
brew "hudochenkov/sshpass/sshpass"  # via tap (use full form so brew bundle dump matches)

# ── Bootstrap deps ──
brew "chezmoi"
brew "bitwarden-cli"
brew "gum"
brew "shellcheck"
brew "bats-core"

# ── Languages / runtimes ──
brew "node"
brew "deno"
brew "python@3.13"
brew "python@3.14"
brew "openjdk@17"
brew "openjdk@21"
brew "go"
brew "rust"

# ── Cloud / dev tooling ──
brew "awscli"
brew "k6"
brew "libpq"
brew "supabase/tap/supabase"  # via tap (use full form so brew bundle dump matches)
brew "gemini-cli"

# ── Media / docs ──
brew "ffmpeg"
brew "yt-dlp"
brew "pandoc"
brew "tectonic"

# ── Fonts ──
cask "font-meslo-lg-nerd-font"

# ── Browsers ──
cask "google-chrome"

# ── Terminals & editors ──
cask "iterm2"
cask "visual-studio-code"
cask "cursor"
cask "bbedit"
cask "antigravity"        # Google Antigravity AI IDE

# ── Dev utilities ──
cask "docker-desktop"
cask "postman"
cask "dbeaver-community"
cask "drawio"
cask "ngrok/ngrok/ngrok"  # via ngrok/ngrok tap (CLI). Tap is required.
cask "auto-claude"        # AndyMik90/Auto-Claude

# ── AI assistants (desktop) ──
cask "claude"
cask "chatgpt"

# ── Productivity / window mgmt ──
cask "rectangle"
cask "stats"
cask "tg-pro"
cask "klokki"

# ── Networking / VPN / remote ──
cask "tailscale-app"      # NB: cask is "tailscale-app", not "tailscale"
cask "tunnelblick"
cask "anydesk"
cask "displaylink"
cask "termius"
cask "windows-app"        # Microsoft's Remote Desktop replacement
cask "amneziavpn"

# ── Communication ──
cask "telegram"
cask "whatsapp"

# ── Utilities ──
cask "bitwarden"
cask "qbittorrent"
cask "outline-manager"    # Jigsaw Outline VPN server manager
cask "yandex-music"
cask "yandextelemost"

# ── Mac App Store apps (no cask available; require signed-in App Store) ──
mas "MKPlayer",                id: 1335612105
mas "Multi Monitor Wallpaper", id: 504284434
mas "Outline",                 id: 1356178125  # Jigsaw VPN client
mas "Speedtest",               id: 1153157709
mas "WireGuard",               id: 1451685025
mas "Microsoft Excel",         id: 462058435
mas "Microsoft PowerPoint",    id: 462062816
mas "Microsoft Word",          id: 462054704

# ── Manual install (no cask, no MAS) ──
# Run these by hand after the bootstrap completes:
#
#   - Astropad Workbench    https://astropad.com/workbench
#   - ChatLLM               https://chatllm.abacus.ai/
#   - CommandShift          https://commandshift.app/
#   - Movavi Video Editor   https://www.movavi.com/  (paid)
#   - Red Shield VPN        https://redshieldvpn.com/
#   - Rock Planner          (source URL TBD — please update)
#   - Willow Voice          https://willowvoice.com/
#   - eno                   (source URL TBD — please update)
#   - stagewise (Pre-Release) https://github.com/stagewise-io/stagewise
#
# Non-brew toolchains installed via curl/installer (covered by Plan 1.5):
#   - oh-my-zsh        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
#   - powerlevel10k    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
#   - nvm              curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
#   - pnpm             curl -fsSL https://get.pnpm.io/install.sh | sh -
#   - maestro          curl -Ls "https://get.maestro.mobile.dev" | bash
