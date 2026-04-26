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
defaults write NSGlobalDomain KeyRepeat -int 3

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
# 左上：Launchpad
defaults write com.apple.dock wvous-tl-corner -int 11
defaults write com.apple.dock wvous-tl-modifier -int 0

# 右上：锁定屏幕
defaults write com.apple.dock wvous-tr-corner -int 13
defaults write com.apple.dock wvous-tr-modifier -int 0

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

# === Xcode & iOS Development Toolchain ===
brew install mas

# NOTE: mas requires an active App Store login. If not signed in,
# run 'open /System/Applications/App\ Store.app' and sign in first.
# echo "Installing Xcode from App Store (this may take 10+ minutes)..."
# mas install 497799835  # Xcode

# sudo xcodebuild -license accept
# xcode-select --switch /Applications/Xcode.app/Contents/Developer
# xcodebuild -runFirstLaunch
# xcodebuild -downloadPlatform iOS

# iOS dev tools
brew install cocoapods swiftlint swiftformat
brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp
gem install xcodeproj

# === CLI Packages ===
brew install azure-cli yq jq
brew install git tree tmux trivy
brew install uv node ruff git-delta
brew install gh glow wget entr
brew install openjdk@21 sing-box zsh python@3.13
brew install frpc libimobiledevice
# If frpc binary disappears (Microsoft Defender quarantines it as Misleading:MacOS/FRP.A!MTB):
#   sudo mdatp exclusion folder add --path /opt/homebrew/Cellar/frpc/
#   brew reinstall frpc

# Override macOS system python3 (3.9.6) with Homebrew's
ln -sf /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3

# bun
curl -fsSL https://bun.sh/install | bash

# === GUI Applications ===
brew install --cask google-chrome visual-studio-code
brew install --cask sublime-text obsidian docker
brew install --cask ghostty
brew install --cask git-credential-manager

# === VS Code Extensions ===
code --install-extension github.copilot
code --install-extension github.copilot-chat
code --install-extension ms-python.python
code --install-extension panxiaoan.themes-falcon-vscode

# === Git Config ===
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/gitconfig -o $HOME/.gitconfig

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

# === Xcode Developer Mode ===
if DevToolsSecurity -status 2>&1 | grep -q "disabled"; then
  sudo DevToolsSecurity -enable
fi

# === Repos Directory ===
mkdir -p $HOME/repos

echo "=== macOS Tahoe init complete ==="
echo "Please restart your terminal or run: source ~/.zshrc"
