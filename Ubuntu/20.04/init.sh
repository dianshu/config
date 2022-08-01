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
apt install -y build-essential procps curl file git

# git
git config --global alias.l "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
git config --global log.date "format-local:%Y-%m-%d %H:%M:%S"
git config --global core.editor vim
git config --global --replace-all user.name ${GitUserName}
git config --global --replace-all user.email ${GitUserEmail}

# ssh key
rm -f /home/${UserName}/.ssh/id_rsa /home/${UserName}/.ssh/id_rsa.pub
mkdir -p /home/${UserName}/.ssh
ssh-keygen -t rsa -b 4096 -C ${GitUserEmail} -f /home/${UserName}/.ssh/id_rsa -N ''
echo "ssh-public-key: " `cat /home/${UserName}/.ssh/id_rsa.pub`

sudo -u ${UserName} /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/20.04/user-specific.sh?${RANDOM})"
