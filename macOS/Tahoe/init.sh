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

# === User Input ===
read -p "Git User Name: " GitUserName
read -p "Git User Email: " GitUserEmail

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

# === CLI Packages ===
brew install azure-cli yq jq
brew install git tree tmux trivy
brew install uv node ruff git-delta
brew install gh frpc glow wget
brew install openjdk@21 sing-box zsh

# bun
curl -fsSL https://bun.sh/install | bash

# === GUI Applications ===
brew install --cask google-chrome visual-studio-code
brew install --cask sublime-text obsidian docker
brew tap manaflow-ai/cmux
brew install --cask cmux

# === VS Code Extensions ===
code --install-extension github.copilot
code --install-extension github.copilot-chat
code --install-extension ms-python.python
code --install-extension panxiaoan.themes-falcon-vscode

# === Git Config ===
curl -fsSL https://raw.githubusercontent.com/dianshu/config/main/gitconfig -o $HOME/.gitconfig
git config --global --replace-all user.name "$GitUserName"
git config --global --replace-all user.email "$GitUserEmail"
git config --global credential.helper osxkeychain

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

# === Repos Directory ===
mkdir -p $HOME/repos

echo "=== macOS Tahoe init complete ==="
echo "Please restart your terminal or run: source ~/.zshrc"
