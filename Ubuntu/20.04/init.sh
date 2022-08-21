#! /bin/bash
set -euo pipefail
shopt -s inherit_errexit

# set env
read -p "User Name: " UserName
export UserName=${UserName}

read -p "Git User Name: " GitUserName
read -p "Git User Email: " GitUserEmail

# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "${UserName}  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${UserName}

# upgrade existing packages
apt update && apt upgrade -y

# timezone related work
export TZ=Asia/Shanghai
DEBIAN_FRONTEND=noninteractive apt install -y tzdata
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install basic packages
apt install -y build-essential procps curl file git software-properties-common apt-transport-https wget

# vscode related work
wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | apt-key add -
add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
apt install -y code

# install vscode extensions
code \
    --install-extension adpyke.codesnap \
    --install-extension eamodio.gitlens \
    --install-extension hediet.vscode-drawio \
    --install-extension ms-azure-devops.azure-pipelines \
    --install-extension ms-dotnettools.csharp \
    --install-extension ms-dotnettools.vscode-dotnet-runtime \
    --install-extension ms-python.python \
    --install-extension ms-python.vscode-pylance \
    --install-extension ms-toolsai.jupyter \
    --install-extension ms-toolsai.jupyter-keymap \
    --install-extension ms-toolsai.jupyter-renderers \
    --install-extension ms-vscode-remote.remote-wsl \
    --install-extension ms-vscode.azure-account \
    --install-extension redhat.vscode-yaml

# git
git config --global alias.l "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
git config --global log.date "format-local:%Y-%m-%d %H:%M:%S"
git config --global core.editor vim
git config --global --replace-all user.name ${GitUserName}
git config --global --replace-all user.email ${GitUserEmail}

sudo -u ${UserName} /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/20.04/user-specific.sh?${RANDOM})"
