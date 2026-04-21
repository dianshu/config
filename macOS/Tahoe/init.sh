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

# === Timezone ===
sudo systemsetup -settimezone Asia/Shanghai

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
echo "Installing Xcode from App Store (this may take 10+ minutes)..."
mas install 497799835  # Xcode

sudo xcodebuild -license accept
xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

# iOS dev tools
brew install cocoapods swiftlint swiftformat

# === CLI Packages ===
brew install azure-cli yq jq git tree tmux trivy uv node ruff git-delta gh frpc glow openjdk@21 sing-box zsh

# bun
curl -fsSL https://bun.sh/install | bash

# === GUI Applications ===
brew install --cask google-chrome microsoft-edge visual-studio-code sublime-text ghostty obsidian docker

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