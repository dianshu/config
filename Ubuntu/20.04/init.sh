#! /bin/bash

# set env
export username=${SUDO_USER:-`whoami`}
echo "Current User: ${username}"

read -p "Git User Name: " GitUserName
read -p "Git User Email: " GitUserEmail

# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "${username}  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${username}

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
git config --global user.name ${GitUserName}
git config --global user.email ${GitUserEmail}

# ssh key
ssh-keygen -t rsa -b 4096 -C ${GitUserEmail} -f ~/.ssh/id_rsa -N ''
echo "ssh-public-key:\n" `cat id_rsa.pub`

sudo -u ${username} /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/master/Ubuntu/20.04/user-specific.sh)"
