set -euo pipefail
shopt -s inherit_errexit

# install homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

ulimit -n 100000

# install packages
brew install vim azure-cli yq
brew install jq net-tools git tree
brew install trivy

# azure cli
# add ml extension
az extension add --upgrade --yes --name ml
az config set extension.dynamic_install_allow_preview=true
az config set extension.use_dynamic_install=yes_without_prompt

# git
git config --global alias.l "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
git config --global log.date "format-local:%Y-%m-%d %H:%M:%S"
git config --global core.editor vim
git config --global --bool push.autoSetupRemote true
git config --global --replace-all user.name $0
git config --global --replace-all user.email $1
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
git config --global credential.https://dev.azure.com.useHttpPath true
# use git merge
git config --global pull.rebase false

# zsh related work
brew install zsh
curl https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc?${RANDOM} > ~/.zshrc

rm -rf ~/.zsh/plugins/zsh-abbr
git clone --depth 1 --recurse-submodules https://github.com/olets/zsh-abbr ~/.zsh/plugins/zsh-abbr

rm -rf ~/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions

rm -rf ~/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting

rm -rf ~/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 --recurse-submodules https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/plugins/zsh-history-substring-search

# replace "/usr/bin/env zsh" to actually zsh "/home/linuxbrew/.linuxbrew/bin/zsh" to avoid error "/usr/bin/env: 'zsh': Permission denied"
find ~/.zsh/plugins/ -type f -name "*.zsh" -exec sed -i 's|^#!/usr/bin/env zsh|#!/home/linuxbrew/.linuxbrew/bin/zsh|' {} +

command -v zsh | sudo tee -a /etc/shells
sudo chsh -s `command -v zsh` ${USER}

# vim related work
cat > ~/.vimrc << EOF
" Doc: https://linuxhint.com/vimrc_tutorial/

set number
syntax on
set tabstop=4
set autoindent
set expandtab
set cursorline
set wildmenu
set showmatch
set incsearch
set hlsearch
set foldenable
set foldlevelstart=10
set foldmethod=indent
set backspace=indent,eol,start

set cursorcolumn
set cursorline
highlight CursorLine   cterm=NONE ctermbg=black ctermfg=yellow
EOF

if uname -a | grep -qi "WSL"; then
    # add wsl.conf
    sudo wget https://raw.githubusercontent.com/dianshu/config/master/Ubuntu/24.04/wsl.conf -O /etc/wsl.conf

    # use browser in windows
    sudo apt install -y wslu
    echo "export BROWSER=wslview" >> ~/.zshrc
fi

# locale related work
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# prepare git repos
mkdir -p ~/repos
