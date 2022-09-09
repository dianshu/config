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

if uname -a | grep -qi "WSL"; then
    echo 'can not install vscode and related extensions, please install them manually:'
    echo 'code \'
    echo '    --install-extension adpyke.codesnap \'
    echo '    --install-extension eamodio.gitlens \'
    echo '    --install-extension ms-azure-devops.azure-pipelines \'
    echo '    --install-extension ms-python.python \'
    echo '    --install-extension ms-python.vscode-pylance \'
    echo '    --install-extension ms-toolsai.jupyter \'
    echo '    --install-extension ms-toolsai.jupyter-keymap \'
    echo '    --install-extension ms-toolsai.jupyter-renderers \'
    echo '    --install-extension ms-vscode-remote.remote-wsl \'
    echo '    --install-extension ms-vscode.azure-account \'
    echo '    --install-extension redhat.vscode-yaml'
    echo ''
else
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
    sudo apt install -y code

    # install vscode extensions
    code \
        --install-extension adpyke.codesnap \
        --install-extension eamodio.gitlens \
        --install-extension ms-azure-devops.azure-pipelines \
        --install-extension ms-python.python \
        --install-extension ms-python.vscode-pylance \
        --install-extension ms-toolsai.jupyter \
        --install-extension ms-toolsai.jupyter-keymap \
        --install-extension ms-toolsai.jupyter-renderers \
        --install-extension ms-vscode-remote.remote-wsl \
        --install-extension ms-vscode.azure-account \
        --install-extension redhat.vscode-yaml
fi

# ssh key
rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
mkdir -p ~/.ssh
ssh-keygen -t rsa -b 4096 -C "ubuntu" -f ~/.ssh/id_rsa -N ''
echo "ssh-public-key:\n" `cat ~/.ssh/id_rsa.pub`
