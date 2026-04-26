#! /bin/bash
set -euo pipefail
shopt -s inherit_errexit

# set env
export UserName=${SUDO_USER:-$(logname)}

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

sudo -u ${UserName} /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/user-specific.sh?${RANDOM})" ${UserName}
