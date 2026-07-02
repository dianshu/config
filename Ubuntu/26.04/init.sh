#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit

# === Preflight ===
if [[ "$(uname)" != "Linux" ]] || ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    echo "ERROR: This script is for Ubuntu only." >&2
    exit 1
fi
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run as root. Run as your normal user; sudo is invoked as needed." >&2
    exit 1
fi

# === Passwordless sudo for daily use ===
# Tradeoff: any process running as you can become root without prompt.
# Kept because daily workflow (apt/systemctl/etc.) depends on it.
# Configured FIRST so re-runs of this script never re-prompt for a password.
SUDOERS_FILE="/etc/sudoers.d/${USER}"
SUDOERS_LINE="${USER} ALL=(ALL) NOPASSWD:ALL"
SUDO_KEEPALIVE_PID=""
if sudo -n test -f "$SUDOERS_FILE" 2>/dev/null && sudo -n grep -qxF "$SUDOERS_LINE" "$SUDOERS_FILE" 2>/dev/null; then
    echo "Passwordless sudo for ${USER} already configured."
else
    # Need one password prompt to bootstrap NOPASSWD. Keepalive covers the few
    # seconds until the sudoers file lands; after that sudo -n succeeds forever.
    sudo -v
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT
    echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    sudo visudo -c -f "$SUDOERS_FILE" >/dev/null
    echo "Passwordless sudo for ${USER} configured."
fi

# === System Update & Timezone ===
sudo apt update && sudo apt upgrade -y

export TZ=Asia/Shanghai
sudo DEBIAN_FRONTEND=noninteractive apt install -y tzdata
sudo ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ | sudo tee /etc/timezone > /dev/null

# === Base Packages ===
sudo apt install -y build-essential procps curl file git software-properties-common apt-transport-https wget libicu-dev

# === Docker ===
if ! command -v docker &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://get.docker.com/)"
fi
sudo usermod -aG docker "${USER}"

# === Homebrew ===
if command -v brew &>/dev/null; then
    echo "Homebrew already installed, updating..."
    brew update
    brew upgrade -y
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
            brew upgrade -f -y $cask "$pkg"
        else
            brew install -y $cask "$pkg"
        fi
    done
}

# === CLI Packages ===
brew_install azure-cli yq jq
brew_install git tree tmux trivy coreutils
brew_install uv node ruff git-delta
brew_install gh glow wget entr
brew tap reviewdog/tap 2>/dev/null || true && brew_install reviewdog/tap/reviewdog
brew_install openjdk@21 sing-box zsh python@3.13
brew_install frpc net-tools

# bun (use `bun upgrade` to update; cc_sync handles that)
command -v bun &>/dev/null || curl -fsSL https://bun.sh/install | bash

# === Sing-box ===
mkdir -p $HOME/.sing-box
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/refs/heads/main/sing-box.config.json -o $HOME/.sing-box/config.json

# === Azure CLI Config ===
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# === Git Config ===
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/git/config -o $HOME/.gitconfig
mkdir -p $HOME/.config/git
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/git/ignore -o $HOME/.config/git/ignore

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
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc" -o $HOME/.zshrc

# 同步 zsh/*.zsh（顶层）到 ~/.zsh/
mkdir -p $HOME/.zsh
for f in prompt; do
    curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/${f}.zsh" -o "$HOME/.zsh/${f}.zsh"
done

mkdir -p $HOME/.zsh/plugins

clone_or_update() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" pull --ff-only --recurse-submodules
    else
        rm -rf "$dest"
        git clone --depth 1 --recurse-submodules "$url" "$dest"
    fi
}

clone_or_update https://github.com/olets/zsh-abbr $HOME/.zsh/plugins/zsh-abbr
clone_or_update https://github.com/zsh-users/zsh-autosuggestions $HOME/.zsh/plugins/zsh-autosuggestions
clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting $HOME/.zsh/plugins/zsh-syntax-highlighting
clone_or_update https://github.com/zsh-users/zsh-history-substring-search $HOME/.zsh/plugins/zsh-history-substring-search

# replace "/usr/bin/env zsh" to actually zsh "/home/linuxbrew/.linuxbrew/bin/zsh" to avoid error "/usr/bin/env: 'zsh': Permission denied"
find $HOME/.zsh/plugins/ -type f -name "*.zsh" -exec sed -i 's|^#!/usr/bin/env zsh|#!/home/linuxbrew/.linuxbrew/bin/zsh|' {} +

ZSH_PATH="$(command -v zsh)"
grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells
sudo chsh -s "$ZSH_PATH" "${USER}"

# === Vim Config ===
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/vimrc" -o $HOME/.vimrc

# === Tmux Config ===
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/tmux/.tmux.conf" -o $HOME/.tmux.conf

# === WSL Config ===
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    sudo curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/26.04/wsl.conf -o /etc/wsl.conf
    sudo curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/26.04/resolved.conf -o /etc/systemd/resolved.conf

    # Open URLs/files in Windows default app via pwsh (PowerShell 7, always installed on host).
    # Replaces wslu/wslview: wslutilities PPA doesn't build for 26.04 yet, and pwsh's
    # Start-Process passes args via ShellExecute, avoiding cmd.exe's &/% escaping pitfalls.
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/wslview" <<'EOF'
#!/bin/sh
exec pwsh.exe -NoProfile -Command "Start-Process" "$@" 2>/dev/null
EOF
    chmod +x "$HOME/.local/bin/wslview"
    grep -qxF "export BROWSER=wslview" "$HOME/.zshrc" || echo "export BROWSER=wslview" >> "$HOME/.zshrc"
fi

# === Locale ===
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# === Repos Directory ===
mkdir -p $HOME/repos

echo "=== Ubuntu 26.04 init complete ==="
echo "Please restart your terminal or run: source ~/.zshrc"
