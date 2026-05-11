#!/bin/bash
set -euo pipefail

# === Preflight ===
if [[ "$(uname)" != "Darwin" ]]; then
    echo "ERROR: This script is for macOS only." >&2
    exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "ERROR: This script is for Apple Silicon (arm64) only." >&2
    exit 1
fi

# === Asset loader (supports both local invocation and `bash <(curl ...)`) ===
RAW_BASE_URL="https://raw.githubusercontent.com/dianshu/config/HEAD/macOS/Tahoe"
get_asset() {
    local name="$1"
    if [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]]; then
        curl -fsSL "$RAW_BASE_URL/$name"
    else
        cat "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$name"
    fi
}

# === TrackPad ===
# 轻点替代点按（Tap to Click）
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

# 拖移手势（三指拖移）
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

# 跟踪速度（0~3，默认约1）
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 1.5

# 自然滚动方向（true=自然，false=传统）
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool true

# 右键点击（双指点击）
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true

# 鼠标光标大小设置成 2
defaults write "Apple Global Domain" cursorSize -float 2.0

# 关闭 点按墙纸以显示桌面
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

# === Keyboard ===
# 按键重复速率（越小越快，默认 6）
defaults write NSGlobalDomain KeyRepeat -int 2

# 重复前延迟（越小越快，默认 25）
defaults write NSGlobalDomain InitialKeyRepeat -int 10

# === Dock ===
# 开启放大效果
defaults write com.apple.dock magnification -bool true

# 放大比例（64~256）
defaults write com.apple.dock largesize -float 94

# 图标默认大小
defaults write com.apple.dock tilesize -float 35

# 最小化窗口动画效果（genie/scale/suck）
defaults write com.apple.dock mineffect -string "genie"

# 将窗口最小化至应用程序图标
defaults write com.apple.dock minimize-to-application -bool true

# === Hot Corners ===
# 左下：锁定屏幕
defaults write com.apple.dock wvous-bl-corner -int 13
defaults write com.apple.dock wvous-bl-modifier -int 0

killall Dock
# === Homebrew ===
if command -v brew &>/dev/null; then
    echo "Homebrew already installed, updating..."
    brew update
else
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
brew doctor

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

# === Xcode & iOS Development Toolchain ===
brew_install mas

# NOTE: mas requires an active App Store login. If not signed in,
# run 'open /System/Applications/App\ Store.app' and sign in first.
# echo "Installing Xcode from App Store (this may take 10+ minutes)..."
# mas install 497799835  # Xcode

# sudo xcodebuild -license accept
# xcode-select --switch /Applications/Xcode.app/Contents/Developer
# xcodebuild -runFirstLaunch
# xcodebuild -downloadPlatform iOS

# iOS dev tools
brew_install cocoapods swiftlint swiftformat
brew tap getsentry/xcodebuildmcp 2>/dev/null || true && brew_install xcodebuildmcp
gem install xcodeproj
# pymobiledevice3: check for updates, use sudo to fix permissions if needed
PMD3_TOOL_DIR="$HOME/.local/share/uv/tools/pymobiledevice3"
PMD3_INSTALLED=$(uv tool list 2>/dev/null | sed -n 's/^pymobiledevice3 \([0-9.]*\).*/\1/p')
if [[ -z "$PMD3_INSTALLED" ]]; then
    echo "Installing pymobiledevice3..."
    uv tool install pymobiledevice3
elif ! pymobiledevice3 -h &>/dev/null; then
    echo "pymobiledevice3 is broken, reinstalling..."
    [[ -d "$PMD3_TOOL_DIR" ]] && sudo chown -R "$(whoami)" "$PMD3_TOOL_DIR"
    uv tool install --force pymobiledevice3
else
    echo "Upgrading pymobiledevice3..."
    if [[ -d "$PMD3_TOOL_DIR" ]] && ! uv tool install --upgrade pymobiledevice3 2>/dev/null; then
        sudo chown -R "$(whoami)" "$PMD3_TOOL_DIR"
        uv tool install --force pymobiledevice3
    fi
fi

# Passwordless sudo for pymobiledevice3 (required by wda-up.sh and any flow
# that runs `pymobiledevice3 developer dvt …` non-interactively). sudoers
# matches the resolved binary path, so resolve the symlink before writing.
PMD3_REAL="$(readlink -f "$(command -v pymobiledevice3)")"
PMD3_SUDOERS="/etc/sudoers.d/pymobiledevice3"
PMD3_SUDOERS_LINE="$(whoami) ALL=(root) NOPASSWD: ${PMD3_REAL}"
if ! sudo test -f "$PMD3_SUDOERS" || ! sudo grep -qxF "$PMD3_SUDOERS_LINE" "$PMD3_SUDOERS"; then
    echo "$PMD3_SUDOERS_LINE" | sudo tee "$PMD3_SUDOERS" > /dev/null
    sudo chmod 440 "$PMD3_SUDOERS"
    sudo visudo -c -f "$PMD3_SUDOERS" >/dev/null
    echo "Passwordless sudo for pymobiledevice3 configured."
else
    echo "Passwordless sudo for pymobiledevice3 already configured."
fi

# pymobiledevice3 tunneld (iOS 17+ device screenshot/debug requires root tunnel)
TUNNELD_PLIST="/Library/LaunchDaemons/com.pymobiledevice3.tunneld.plist"
if [[ ! -f "$TUNNELD_PLIST" ]]; then
    PMD3_BIN="$(which pymobiledevice3)"
    get_asset "com.pymobiledevice3.tunneld.plist" | sed "s|__PMD3_BIN__|${PMD3_BIN}|g" | sudo tee "$TUNNELD_PLIST" > /dev/null
    sudo launchctl load "$TUNNELD_PLIST"
    echo "pymobiledevice3 tunneld installed and started."
else
    echo "pymobiledevice3 tunneld already configured, skipping."
fi

# keep_alive_iphone LaunchAgent (depends on tunneld + ~/.zsh_scripts/keep_alive_iphone synced via .zshrc)
KEEP_ALIVE_PLIST="$HOME/Library/LaunchAgents/com.user.keep-alive-iphone.plist"
KEEP_ALIVE_SCRIPT="$HOME/.zsh_scripts/keep_alive_iphone"
KEEP_ALIVE_LOG_DIR="$HOME/Library/Logs"
mkdir -p "$(dirname "$KEEP_ALIVE_PLIST")" "$KEEP_ALIVE_LOG_DIR" "$(dirname "$KEEP_ALIVE_SCRIPT")"
# Bootstrap the script directly so the LaunchAgent has something to run before
# the first interactive zsh session syncs ~/.zsh_scripts/.
curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/scripts/keep_alive_iphone" \
    -o "$KEEP_ALIVE_SCRIPT"
chmod +x "$KEEP_ALIVE_SCRIPT"
# Render plist with current PATH so launchd's clean env can find brew/uv tools.
KEEP_ALIVE_PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
NEW_PLIST_CONTENT="$(get_asset "com.user.keep-alive-iphone.plist" | sed \
    -e "s|__SCRIPT_PATH__|${KEEP_ALIVE_SCRIPT}|g" \
    -e "s|__PATH__|${KEEP_ALIVE_PATH}|g" \
    -e "s|__LOG_DIR__|${KEEP_ALIVE_LOG_DIR}|g")"
if [[ ! -f "$KEEP_ALIVE_PLIST" ]] || ! diff -q <(echo "$NEW_PLIST_CONTENT") "$KEEP_ALIVE_PLIST" &>/dev/null; then
    echo "$NEW_PLIST_CONTENT" > "$KEEP_ALIVE_PLIST"
    launchctl bootout "gui/$(id -u)/com.user.keep-alive-iphone" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$KEEP_ALIVE_PLIST"
    echo "keep-alive-iphone LaunchAgent installed/updated."
else
    launchctl print "gui/$(id -u)/com.user.keep-alive-iphone" &>/dev/null \
        || launchctl bootstrap "gui/$(id -u)" "$KEEP_ALIVE_PLIST"
    echo "keep-alive-iphone LaunchAgent already configured."
fi

# === CLI Packages ===
brew_install azure-cli yq jq
brew_install git tree tmux trivy coreutils
brew_install uv node ruff git-delta
brew_install gh glow wget entr
brew_install openjdk@21 sing-box zsh python@3.13
brew_install frpc libimobiledevice
# If frpc binary disappears (Microsoft Defender quarantines it as Misleading:MacOS/FRP.A!MTB):
#   sudo mdatp exclusion folder add --path /opt/homebrew/Cellar/frpc/
#   brew reinstall frpc
brew_install displayplacer

# Override macOS system python3 (3.9.6) with Homebrew's
ln -sf /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3

# bun
curl -fsSL https://bun.sh/install | bash

# === GUI Applications ===
brew_install --cask google-chrome visual-studio-code
brew_install --cask sublime-text obsidian docker
brew_install --cask ghostty
brew_install --cask git-credential-manager

# === VS Code Extensions ===
code --install-extension ms-python.python
code --install-extension panxiaoan.themes-falcon-vscode

# === Git Config ===
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/git/config -o $HOME/.gitconfig
mkdir -p $HOME/.config/git
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/git/ignore -o $HOME/.config/git/ignore

# Silent credential refresh: GitHub via gh keyring, Azure DevOps via macOS Platform SSO broker.
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
git config --global credential.msauthUseBroker true

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

# === Zsh Plugins & Config ===
curl -fsSL "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc?${RANDOM}" -o $HOME/.zshrc

mkdir -p $HOME/.zsh/plugins

rm -rf $HOME/.zsh/plugins/zsh-abbr
git clone --depth 1 --recurse-submodules https://github.com/olets/zsh-abbr $HOME/.zsh/plugins/zsh-abbr

rm -rf $HOME/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-autosuggestions $HOME/.zsh/plugins/zsh-autosuggestions

rm -rf $HOME/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-syntax-highlighting $HOME/.zsh/plugins/zsh-syntax-highlighting

rm -rf $HOME/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-history-substring-search $HOME/.zsh/plugins/zsh-history-substring-search

# === Vim Config ===
wget https://raw.githubusercontent.com/dianshu/config/refs/heads/main/vimrc -O $HOME/.vimrc

# === Sing-box ===
mkdir -p $HOME/.sing-box
curl -fsSL https://raw.githubusercontent.com/dianshu/config/refs/heads/main/sing-box.config.json -o $HOME/.sing-box/config.json

# === Azure CLI Config ===
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# === Touch ID for sudo ===
# Enable Touch ID authentication for sudo via /etc/pam.d/sudo_local
# (survives macOS updates, unlike editing /etc/pam.d/sudo directly).
if [[ ! -f /etc/pam.d/sudo_local ]] || ! grep -q '^auth.*pam_tid.so' /etc/pam.d/sudo_local; then
    echo "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null
    echo "Touch ID for sudo enabled."
else
    echo "Touch ID for sudo already enabled."
fi

# === Xcode Developer Mode ===
if DevToolsSecurity -status 2>&1 | grep -q "disabled"; then
  sudo DevToolsSecurity -enable
fi

# === Repos Directory ===
mkdir -p $HOME/repos

echo "=== macOS Tahoe init complete ==="
echo "Please restart your terminal or run: source ~/.zshrc"
