# add sudo right to current user
mkdir -p /etc/sudoers.d/
echo "`whoami`  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/`whoami`

# upgrade packages
apt update && apt upgrade -y

# timezone related work
export DEBIAN_FRONTEND=noninteractive
export TZ=Asia/Shanghai
apt install -y tzdata
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

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

rm -rf ~/.zsh/plugins/zsh-history-substring-search
git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/plugins/zsh-history-substring-search

# install homebrew
apt install -y build-essential procps curl file git
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor

# install packages
brew install vim kubectl azure-cli yq