#! /bin/bash
export username=${SUDO_USER:-`whoami`}

# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "${username}  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${username}

# upgrade packages
apt update && apt upgrade -y

# timezone related work
export TZ=Asia/Shanghai
DEBIAN_FRONTEND=noninteractive apt install -y tzdata
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# zsh related work
apt install -y zsh
curl https://raw.githubusercontent.com/dianshu/config/master/zsh/.zshrc > /home/${username}/.zshrc
chsh -s `which zsh` ${username}

rm -rf /home/${username}/.zsh/plugins/zsh-abbr
git clone --depth 1 https://github.com/olets/zsh-abbr /home/${username}/.zsh/plugins/zsh-abbr

rm -rf /home/${username}/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions /home/${username}/.zsh/plugins/zsh-autosuggestions

rm -rf /home/${username}/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting /home/${username}/.zsh/plugins/zsh-syntax-highlighting

rm -rf /home/${username}/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search /home/${username}/.zsh/plugins/zsh-history-substring-search

# install homebrew
apt install -y build-essential procps curl file git
NONINTERACTIVE=1 su - ${username} -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

# install packages
brew install vim kubectl azure-cli yq jq npm
npm install -g tldr
