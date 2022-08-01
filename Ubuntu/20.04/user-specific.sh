set -euo pipefail
shopt -s inherit_errexit

# install homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

# install packages
brew install vim kubectl azure-cli yq jq npm
npm install -g tldr

# zsh related work
brew install zsh
curl https://raw.githubusercontent.com/dianshu/config/HEAD/zsh/.zshrc > ~/.zshrc

rm -rf ~/.zsh/plugins/zsh-abbr
git clone --depth 1 https://github.com/olets/zsh-abbr ~/.zsh/plugins/zsh-abbr

rm -rf ~/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions

rm -rf ~/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting

rm -rf ~/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/plugins/zsh-history-substring-search

command -v zsh | sudo tee -a /etc/shells
sudo chsh -s `command -v zsh` ${SUDO_USER:-`whoami`}

# vim related work
cat > ~/.vimrc << EOF
set number
syntax on
set tabstop=4
set autoindent
set expandtab
set cursorline
EOF

# python related work
brew install python3
Python3Path=`which python3`
Python3Dir=`dirname ${Python3Path}`
ln -sf ${Python3Path} ${Python3Dir}/python

Pip3Path=`which pip3`
Pip3Dir=`dirname ${Pip3Path}`
ln -sf ${Pip3Path} ${Pip3Dir}/pip

pip install ipython requests venv
