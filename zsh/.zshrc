# 启用插件 abbr-zsh
# 这个插件会在 /tmp 目录下创建目录来存储命令别名，因此可能会存在权限问题
source ~/.zsh/plugins/zsh-abbr/zsh-abbr.zsh
chmod 777 -R /tmp/zsh-abbr 2&> /dev/null
source ~/.zsh/plugins/zsh-abbr/zsh-abbr.zsh

# 启用其他插件
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# 启动历史命令搜索插件
source ~/.zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
# Linux & Mac
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
# Window
# bindkey '^[OA' history-substring-search-up
# bindkey '^[OB' history-substring-search-down

# 启用彩色提示符
autoload -U colors && colors

# 每次刷新提示符
setopt prompt_subst

# 设置提示符
PROMPT='❰%{$reset_color%}%{$fg[red]%}[$(TZ="Asia/Shanghai" date +%H:%M)]%{$reset_color%}%F{#41C4C2}%n%{$reset_color%}|%{$fg[yellow]%}%1~%{$reset_color%}%F{#5DC441}$(git branch --show-current 2&> /dev/null | xargs -I branch echo "(branch)")%{$reset_color%}❱
%F{#FC7E00}%#%{$reset_color%} '

# 设置常用的命令别名
abbr --quiet -S gl='git l'
abbr --quiet -S gp='git push'
abbr --quiet -S gb='git branch'
abbr --quiet -S gs='git status'
abbr --quiet -S gco='git checkout'
abbr --quiet -S gbd='git branch --merged | grep --color=auto -v "master" | xargs -L 1 -p git branch -d'
abbr --quiet -S check='git status --porcelain | awk "/.py/ {print \$2}" | xargs -t flake8 --max-line-length=120'
abbr --quiet -S check2='git status --porcelain | awk "/.py/ {print \$2}" | cut -c 24- | xargs -t flake8 --max-line-length=120'
abbr --quiet -S grep='grep --color=auto'
abbr --quiet -S k='kubectl'

# 启用路径自动补全
autoload -Uz compinit
compinit

# 保存命令历史记录
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history

# 命令即时写入历史，而不是等 shell 退出后再写入
setopt INC_APPEND_HISTORY

# 命令搜索时只展示非重复的命令
setopt HIST_FIND_NO_DUPS

# 命令写入历史时仅写入非重复的命令
setopt HIST_IGNORE_ALL_DUPS

# 索引 snap 安装的命令
export PATH=/snap:$PATH

# 引入 homebrew 相关环境变量
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# 启用 k8s 命令自动补全
# source <(kubectl completion zsh)

# 启用 az-cli 命令自动补全
autoload -U +X bashcompinit && bashcompinit
source /home/linuxbrew/.linuxbrew/etc/bash_completion.d/az

# enable docker buildkit
export DOCKER_BUILDKIT=1

####################################################################################
#                                     Functions                                    #
####################################################################################
function docker_build() {
    docker build --add-host $(ifconfig eth0 | grep "inet " | awk '{print "host.docker.internal:"$2}') $@
}

function docker_run() {
    docker run --init --rm $@                                                                                                                  
}  
