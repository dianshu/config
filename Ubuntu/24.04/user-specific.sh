set -euo pipefail
shopt -s inherit_errexit

# === Docker ===
/bin/bash -c "$(curl -fsSL https://get.docker.com/)"
sudo usermod -aG docker ${USER}

# === Homebrew ===
if command -v brew &>/dev/null; then
    echo "Homebrew already installed, updating..."
    brew update
else
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

ulimit -n 100000

# Install or upgrade a brew package
brew_install() {
    local cask=""
    if [[ "$1" == "--cask" ]]; then
        cask="--cask"
        shift
    fi
    for pkg in "$@"; do
        if brew ls --versions $cask "$pkg" &>/dev/null; then
            brew upgrade $cask "$pkg"
        else
            brew install $cask "$pkg"
        fi
    done
}

# === CLI Packages ===
brew_install azure-cli yq jq
brew_install git tree tmux trivy coreutils
brew_install uv node ruff git-delta
brew_install gh glow wget entr
brew_install openjdk@21 sing-box zsh python@3.13
brew_install frpc net-tools

# bun
curl -fsSL https://bun.sh/install | bash

# === Sing-box ===
mkdir -p $HOME/.sing-box
curl -fsSL https://raw.githubusercontent.com/dianshu/config/refs/heads/main/sing-box.config.json -o $HOME/.sing-box/config.json

# === Azure CLI Config ===
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# === Git Config ===
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/git/config -o $HOME/.gitconfig
mkdir -p $HOME/.config/git
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/git/ignore -o $HOME/.config/git/ignore

# Silent credential refresh: GitHub via gh keyring; Azure DevOps via WSL→Windows GCM bridge.
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git

setup_git_identity() {
    local file="$1"
    local label="$2"
    if [[ -f "$file" ]] \
        && [[ -n "$(git config -f "$file" user.name 2>/dev/null)" ]] \
        && [[ -n "$(git config -f "$file" user.email 2>/dev/null)" ]]; then
        echo "$label identity already configured in $file, skipping."
        return
    fi
    read -p "Set up $label git identity? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Skipping $label identity setup."
        return
    fi
    read -p "  User Name: " name
    read -p "  User Email: " email
    if [[ -z "$name" || -z "$email" ]]; then
        echo "Skipping $label identity (empty input)."
        return
    fi
    git config -f "$file" user.name "$name"
    git config -f "$file" user.email "$email"
}

setup_git_identity "$HOME/.gitconfig-github" "GitHub"
setup_git_identity "$HOME/.gitconfig-ado" "Azure DevOps"

# Azure DevOps via Windows GCM (WSL only — overrides gh's https.github.com helper safely
# because the GCM line is global; gh's setup-git scopes its helper to github.com).
gcm_exe=$(find /mnt/c/Programs/Git /mnt/q/Programs/Git -maxdepth 5 -name "git-credential-manager.exe" -type f 2>/dev/null | head -1 || true)
if [ -n "$gcm_exe" ]; then
    git config --global credential.helper "$gcm_exe"
else
    echo "WARNING: git-credential-manager.exe not found on Windows drives"
fi

# === Zsh Plugins & Config ===
curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc?${RANDOM}" -o $HOME/.zshrc

# 同步 zsh/*.zsh（顶层）到 ~/.zsh/
mkdir -p $HOME/.zsh
for f in prompt; do
    curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/${f}.zsh?${RANDOM}" -o "$HOME/.zsh/${f}.zsh"
done

mkdir -p $HOME/.zsh/plugins

rm -rf $HOME/.zsh/plugins/zsh-abbr
git clone --depth 1 --recurse-submodules https://github.com/olets/zsh-abbr $HOME/.zsh/plugins/zsh-abbr

rm -rf $HOME/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-autosuggestions $HOME/.zsh/plugins/zsh-autosuggestions

rm -rf $HOME/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-syntax-highlighting $HOME/.zsh/plugins/zsh-syntax-highlighting

rm -rf $HOME/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-history-substring-search $HOME/.zsh/plugins/zsh-history-substring-search

# replace "/usr/bin/env zsh" to actually zsh "/home/linuxbrew/.linuxbrew/bin/zsh" to avoid error "/usr/bin/env: 'zsh': Permission denied"
find $HOME/.zsh/plugins/ -type f -name "*.zsh" -exec sed -i 's|^#!/usr/bin/env zsh|#!/home/linuxbrew/.linuxbrew/bin/zsh|' {} +

command -v zsh | sudo tee -a /etc/shells
sudo chsh -s `command -v zsh` ${USER}

# === Vim Config ===
curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/vimrc?${RANDOM}" -o $HOME/.vimrc

# === Tmux Config ===
curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/tmux/.tmux.conf?${RANDOM}" -o $HOME/.tmux.conf

# === WSL Config ===
if uname -a | grep -qi "WSL"; then
    sudo curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/24.04/wsl.conf -o /etc/wsl.conf
    sudo curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/24.04/resolved.conf -o /etc/systemd/resolved.conf

    # use browser in windows
    sudo apt install -y wslu
    grep -qxF "export BROWSER=wslview" "$HOME/.zshrc" || echo "export BROWSER=wslview" >> "$HOME/.zshrc"
fi

# === Locale ===
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# === Repos Directory ===
mkdir -p $HOME/repos

# === Mail MCP token keepalive cron ===
# agency mcp mail uses Entra local auth (~60min TTL) and only refreshes
# lazily on next request — poke it every 30min so the first user-visible
# call after idle never hits an expired token.
# Requires `cron` (Ubuntu ships it; in WSL it must be started manually
# unless you use systemd or an autostart hook).
if command -v crontab >/dev/null 2>&1; then
    KA_SCRIPT="$HOME/.zsh_scripts/mail_mcp_keepalive.sh"
    KA_CRON_LINE="*/30 * * * * $KA_SCRIPT >/dev/null 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "$KA_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "$KA_CRON_LINE") | crontab -
        echo "mail MCP keepalive cron installed (every 30min)."
    else
        echo "mail MCP keepalive cron already configured."
    fi
fi

echo "=== Ubuntu 24.04 user-specific init complete ==="
echo "Please restart your terminal or run: source ~/.zshrc"
