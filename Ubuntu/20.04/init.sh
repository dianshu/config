# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "`whoami`  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/`whoami`

# upgrade packages
apt update && apt upgrade -y

# zsh related work
apt install -y zsh
curl https://raw.githubusercontent.com/dianshu/config/master/zsh/.zshrc > ~/.zshrc
chsh -s `which zsh`

rm -rf ~/.zsh/plugins/zsh-abbr
git clone --depth 1 https://github.com/olets/zsh-abbr ~/.zsh/plugins/zsh-abbr

rm -rf ~/.zsh/plugins/zsh-autosuggestions
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions

rm -rf ~/.zsh/plugins/zsh-syntax-highlighting
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting

# install homebrew
apt install -y build-essential procps curl file git
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew doctor

# install packages
brew install gcc vim kubectl azure-cli