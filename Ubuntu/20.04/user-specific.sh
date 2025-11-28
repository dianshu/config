set -euo pipefail
shopt -s inherit_errexit

# install homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

ulimit -n 100000

# install packages
brew install vim kubectl azure-cli yq jq tldr net-tools helm git tree

# git
git config --global alias.l "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
git config --global log.date "format-local:%Y-%m-%d %H:%M:%S"
git config --global core.editor vim
git config --global --bool push.autoSetupRemote true
git config --global --replace-all user.name $0
git config --global --replace-all user.email $1

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

set cursorcolumn
set cursorline
highlight CursorLine   cterm=NONE ctermbg=black ctermfg=yellow
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
    # add wsl.conf
    sudo wget https://raw.githubusercontent.com/dianshu/config/master/Ubuntu/20.04/wsl.conf -O /etc/wsl.conf
    
    # install docker
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker $2
else
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
    sudo apt install -y code
fi

# locale related workd
sudo apt install -y language-pack-zh-hans
sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# ssh key
rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
mkdir -p ~/.ssh
ssh-keygen -t rsa -b 4096 -C "ubuntu" -f ~/.ssh/id_rsa -N ''
echo "ssh-public-key:\n" `cat ~/.ssh/id_rsa.pub`
