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
brew_install cocoapods swiftlint swiftformat xcode-build-server
brew tap getsentry/xcodebuildmcp 2>/dev/null || true && brew_install xcodebuildmcp
gem install xcodeproj
# pymobiledevice3: check for updates, use sudo to fix permissions if needed.
# Pin to Python 3.13+ — iOS 18.2+ removed QUIC, so tunneld must use TCP tunnels,
# which require python3.13+. Default uv pick of 3.10 silently breaks all RemoteXPC
# (tunneld returns {} forever; xcuitest reports "Device is not connected").
PMD3_TOOL_DIR="$HOME/.local/share/uv/tools/pymobiledevice3"
PMD3_PYTHON="3.13"
PMD3_INSTALLED=$(uv tool list 2>/dev/null | sed -n 's/^pymobiledevice3 \([0-9.]*\).*/\1/p')
# Detect interpreter version of the currently-installed tool (empty if not installed).
PMD3_CUR_PY=$("$PMD3_TOOL_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)
pmd3_python_ok() {
    [[ -n "$PMD3_CUR_PY" ]] && \
        awk -v cur="$PMD3_CUR_PY" -v min="$PMD3_PYTHON" 'BEGIN{split(cur,a,".");split(min,b,".");exit !(a[1]>b[1]||(a[1]==b[1]&&a[2]>=b[2]))}'
}
if [[ -z "$PMD3_INSTALLED" ]]; then
    echo "Installing pymobiledevice3 (python $PMD3_PYTHON)..."
    uv tool install --python "$PMD3_PYTHON" pymobiledevice3
elif ! pymobiledevice3 -h &>/dev/null; then
    echo "pymobiledevice3 is broken, reinstalling..."
    [[ -d "$PMD3_TOOL_DIR" ]] && sudo chown -R "$(whoami)" "$PMD3_TOOL_DIR"
    uv tool install --force --python "$PMD3_PYTHON" pymobiledevice3
elif ! pmd3_python_ok; then
    echo "pymobiledevice3 on python $PMD3_CUR_PY < $PMD3_PYTHON (iOS 18.2+ needs TCP tunnel), reinstalling..."
    [[ -d "$PMD3_TOOL_DIR" ]] && sudo chown -R "$(whoami)" "$PMD3_TOOL_DIR"
    uv tool install --force --python "$PMD3_PYTHON" pymobiledevice3
    sudo launchctl kickstart -k system/com.pymobiledevice3.tunneld 2>/dev/null || true
else
    echo "Upgrading pymobiledevice3..."
    if [[ -d "$PMD3_TOOL_DIR" ]] && ! uv tool install --upgrade --python "$PMD3_PYTHON" pymobiledevice3 2>/dev/null; then
        sudo chown -R "$(whoami)" "$PMD3_TOOL_DIR"
        uv tool install --force --python "$PMD3_PYTHON" pymobiledevice3
    fi
fi

# Passwordless sudo for pymobiledevice3 (required by wda-up.sh and any flow
# that runs `pymobiledevice3 developer dvt …` non-interactively). sudoers
# matches the resolved binary path AND must also list the symlink, since
# callers usually invoke `sudo -n pymobiledevice3` via PATH which resolves
# to the symlink — sudo does not chase symlinks when matching rules.
PMD3_LINK="$(command -v pymobiledevice3)"
PMD3_REAL="$(readlink -f "$PMD3_LINK")"
PMD3_SUDOERS="/etc/sudoers.d/pymobiledevice3"
PMD3_SUDOERS_LINE="$(whoami) ALL=(root) NOPASSWD: ${PMD3_REAL}, ${PMD3_LINK}"
# Use a user-readable marker to avoid invoking sudo on every sync run (which
# would prompt for Touch ID even when the rule is already in place — sudoers
# files are 0440 root:wheel, so verifying their content otherwise needs sudo).
PMD3_MARKER="$HOME/.cache/init-sh/pmd3-sudoers.sha"
PMD3_EXPECTED_SHA="$(printf '%s\n' "$PMD3_SUDOERS_LINE" | shasum -a 256 | awk '{print $1}')"
mkdir -p "$(dirname "$PMD3_MARKER")"
if [[ -f "$PMD3_SUDOERS" && "$(cat "$PMD3_MARKER" 2>/dev/null)" == "$PMD3_EXPECTED_SHA" ]]; then
    echo "Passwordless sudo for pymobiledevice3 already configured."
else
    echo "$PMD3_SUDOERS_LINE" | sudo tee "$PMD3_SUDOERS" > /dev/null
    sudo chmod 440 "$PMD3_SUDOERS"
    sudo visudo -c -f "$PMD3_SUDOERS" >/dev/null
    printf '%s' "$PMD3_EXPECTED_SHA" > "$PMD3_MARKER"
    echo "Passwordless sudo for pymobiledevice3 configured."
fi

# Passwordless sudo for /usr/bin/true. Xcode's `devicectl diagnose` (triggered
# by `xcodebuild test` when collecting failure diagnostics) probes sudo cache
# with `sudo true` and pops Touch ID if it can't run silently. `true` is a
# no-op, so granting NOPASSWD on it has zero security cost and silences every
# tool that uses the same probe pattern.
TRUE_SUDOERS="/etc/sudoers.d/sudo-true-probe"
TRUE_SUDOERS_LINE="$(whoami) ALL=(root) NOPASSWD: /usr/bin/true"
TRUE_MARKER="$HOME/.cache/init-sh/true-sudoers.sha"
TRUE_EXPECTED_SHA="$(printf '%s\n' "$TRUE_SUDOERS_LINE" | shasum -a 256 | awk '{print $1}')"
mkdir -p "$(dirname "$TRUE_MARKER")"
if [[ -f "$TRUE_SUDOERS" && "$(cat "$TRUE_MARKER" 2>/dev/null)" == "$TRUE_EXPECTED_SHA" ]]; then
    echo "Passwordless sudo for /usr/bin/true probe already configured."
else
    echo "$TRUE_SUDOERS_LINE" | sudo tee "$TRUE_SUDOERS" > /dev/null
    sudo chmod 440 "$TRUE_SUDOERS"
    sudo visudo -c -f "$TRUE_SUDOERS" >/dev/null
    printf '%s' "$TRUE_EXPECTED_SHA" > "$TRUE_MARKER"
    echo "Passwordless sudo for /usr/bin/true probe configured."
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

# === CLI Packages ===
brew_install azure-cli yq jq
brew_install git tree tmux trivy coreutils
brew_install uv node ruff git-delta
brew_install gh glow wget entr
brew tap reviewdog/tap 2>/dev/null || true && brew_install reviewdog/tap/reviewdog
brew_install openjdk@21 sing-box zsh python@3.13
brew_install frpc libimobiledevice
# If frpc binary disappears (Microsoft Defender quarantines it as Misleading:MacOS/FRP.A!MTB):
#   sudo mdatp exclusion folder add --path /opt/homebrew/Cellar/frpc/
#   brew reinstall frpc
brew_install displayplacer

# Override macOS system python3 (3.9.6) with Homebrew's
ln -sf /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3

# bun (use `bun upgrade` to update; cc_sync handles that)
command -v bun &>/dev/null || curl -fsSL https://bun.sh/install | bash

# === GUI Applications ===
brew_install --cask google-chrome visual-studio-code
brew_install --cask sublime-text obsidian docker
brew_install --cask ghostty
brew_install --cask git-credential-manager
brew_install --cask monitorcontrol  # 外接屏亮度/音量控制 (F1/F2)
brew_install --cask betterdisplay   # screen-builtin on 依赖它启停触发显示重置来恢复内置屏

# === VS Code Extensions ===
code --install-extension ms-python.python
code --install-extension panxiaoan.themes-falcon-vscode

# === Git Config ===
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/git/config -o $HOME/.gitconfig
mkdir -p $HOME/.config/git
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/main/git/ignore -o $HOME/.config/git/ignore

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
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc" -o $HOME/.zshrc

# 同步 zsh/*.zsh（顶层）到 ~/.zsh/
mkdir -p $HOME/.zsh
for f in prompt; do
    curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/${f}.zsh" -o "$HOME/.zsh/${f}.zsh"
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

# === Vim Config ===
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/refs/heads/main/vimrc -o $HOME/.vimrc

# === Tmux Config ===
curl -fsSL -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/dianshu/config/HEAD/tmux/.tmux.conf" -o $HOME/.tmux.conf

# === Sing-box ===
mkdir -p $HOME/.sing-box
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/dianshu/config/refs/heads/main/sing-box.config.json -o $HOME/.sing-box/config.json

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
