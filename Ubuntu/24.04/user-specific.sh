set -euo pipefail
shopt -s inherit_errexit

# install docker
/bin/bash -c "$(curl -fsSL https://get.docker.com/)"
sudo usermod -aG docker ${USER}

# install homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

ulimit -n 100000

# install packages
brew install azure-cli yq
brew install jq net-tools git tree tmux
brew install trivy uv node ruff git-delta
brew install gh frpc glow
brew install openjdk@21
curl -fsSL https://bun.sh/install | bash

# sing-box
brew install sing-box
mkdir -p $HOME/.sing-box
wget https://raw.githubusercontent.com/dianshu/config/main/sing-box.config.json -O $HOME/.sing-box/config.json

# azure cli
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# git
wget https://raw.githubusercontent.com/dianshu/config/main/gitconfig -O $HOME/.gitconfig
git config --global --replace-all user.name $0
git config --global --replace-all user.email $1

gcm_exe=$(find /mnt/c/Programs/Git /mnt/q/Programs/Git -maxdepth 5 -name "git-credential-manager.exe" -type f 2>/dev/null | head -1 || true)
if [ -n "$gcm_exe" ]; then
    git config --global credential.helper "$gcm_exe"
else
    echo "WARNING: git-credential-manager.exe not found on Windows drives"
fi

# zsh related work
brew install zsh
curl https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc?${RANDOM} > $HOME/.zshrc

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

# vim related work
wget https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/24.04/vimrc -O $HOME/.vimrc

if uname -a | grep -qi "WSL"; then
    # add wsl.conf
    sudo wget https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/24.04/wsl.conf -O /etc/wsl.conf
    sudo wget https://raw.githubusercontent.com/dianshu/config/main/Ubuntu/24.04/resolved.conf -O /etc/systemd/resolved.conf

    # use browser in windows
    sudo apt install -y wslu
    echo "export BROWSER=wslview" >> $HOME/.zshrc
fi

# locale related work
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# prepare git repos
mkdir -p $HOME/repos
