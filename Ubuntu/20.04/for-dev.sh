#! /bin/bash
set -euo pipefail
shopt -s inherit_errexit

# upgrade existing packages
apt update && apt upgrade -y

# timezone related work
export TZ=Asia/Shanghai
DEBIAN_FRONTEND=noninteractive apt install -y tzdata
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install basic packages
apt install -y build-essential procps curl file git software-properties-common apt-transport-https wget

# install homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

ulimit -n 100000

# install packages
brew install vim kubectl azure-cli yq jq tldr net-tools helm git tree

# zsh related work
brew install zsh
curl https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc?${RANDOM} > ~/.zshrc

rm -rf ~/.zsh/plugins/zsh-abbr
git clone --depth 1 https://github.com/olets/zsh-abbr ~/.zsh/plugins/zsh-abbr

rm -rf ~/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions

rm -rf ~/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting

rm -rf ~/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/plugins/zsh-history-substring-search

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
EOF

# python related work
brew install python3
Python3Path=`which python3`
Python3Dir=`dirname ${Python3Path}`
ln -sf ${Python3Path} ${Python3Dir}/python

Pip3Path=`which pip3`
Pip3Dir=`dirname ${Pip3Path}`
ln -sf ${Pip3Path} ${Pip3Dir}/pip

python -m pip install --upgrade pip
pip install ipython requests

# locale related workd
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
