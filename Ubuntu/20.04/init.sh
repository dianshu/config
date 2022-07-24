# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "`whoami`  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/`whoami`

# upgrade packages
apt update && apt upgrade -y

# zsh related work
apt install -y zsh
mv .zshrc ~/
chsh -s `which zsh`

# install homebrew
apt install -y build-essential procps curl file git
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew doctor

# install packages
brew install gcc vim kubectl azure-cli