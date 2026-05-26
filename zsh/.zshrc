# === 启动性能日志 ===
zmodload zsh/datetime
typeset -g _zshrc_start=$EPOCHREALTIME
typeset -g _zshrc_last=$EPOCHREALTIME
typeset -g _zshrc_log=~/.zsh_startup.log
typeset -ga _zshrc_marks=()
typeset -g _zshrc_os=$(uname)
_zshrc_mark() {
    local now=$EPOCHREALTIME
    _zshrc_marks+=("$(printf '  %-28s %6.0fms (+%4.0fms)' "$1" "$(( (now - _zshrc_start) * 1000 ))" "$(( (now - _zshrc_last) * 1000 ))")")
    _zshrc_last=$now
}

# 启用插件 abbr-zsh
# zsh-abbr stores temp data in /tmp/zsh-abbr; fix perms before sourcing
[[ -d /tmp/zsh-abbr ]] && chmod 700 /tmp/zsh-abbr 2>/dev/null
source ~/.zsh/plugins/zsh-abbr/zsh-abbr.zsh
_zshrc_mark "zsh-abbr"

# 启用其他插件
source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
_zshrc_mark "autosuggestions"
source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
_zshrc_mark "syntax-highlighting"

# 启动历史命令搜索插件
source ~/.zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
_zshrc_mark "history-substring-search"
# Linux & Mac
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
# Window
# bindkey '^[OA' history-substring-search-up
# bindkey '^[OB' history-substring-search-down

# 启用彩色提示符
autoload -U colors && colors
_zshrc_mark "colors"

# 提示符配置（详见独立文件）
source ~/.zsh/prompt.zsh
_zshrc_mark "prompt"

# Direct session abbreviation loading — bypasses abbr command overhead.
# Coupled to zsh-abbr v6.4.0 internals: keys/values use ${(qqq)...} quoting
# (literal double quotes). If zsh-abbr is upgraded, verify this still works.
ABBR_REGULAR_SESSION_ABBREVIATIONS+=(
  '"cc"'     '"hapi"'
  '"ccc"'    '"cc_clean"'
  '"ccp"'    '"cc_proxy"'
  '"ccr"'    '"cc_remote"'
  '"ccrs"'   '"cc_remote_stop"'
  '"ccs"'    '"cc_sync"'
  '"d"'      '"docker"'
  '"dc"'     '"docker compose"'
  '"gco"'    '"git checkout"'
  '"gcm"'    '"git checkout main && git pull"'
  '"gl"'     '"git l"'
  '"gp"'     '"git push"'
  '"gb"'     '"git branch"'
  '"grep"'   '"grep --color=auto"'
  '"gs"'     '"git status"'
  '"k"'      '"kubectl"'
  '"ll"'     '"ls -lah"'
)
_zshrc_mark "abbr definitions"

# 启用路径自动补全
autoload -Uz compinit
_zcompdump_fresh=( "${ZDOTDIR:-$HOME}"/.zcompdump(Nmh-24) )
if (( $#_zcompdump_fresh )); then
  compinit -C
else
  compinit
fi
unset _zcompdump_fresh
_zshrc_mark "compinit"

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
if [[ "$_zshrc_os" != "Darwin" ]]; then
    export PATH=/snap:$PATH
fi

# 引入 homebrew 相关环境变量
if [[ "$_zshrc_os" == "Darwin" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
_zshrc_mark "brew shellenv"

# Homebrew Ruby (keg-only, override system Ruby)
if [[ "$_zshrc_os" == "Darwin" ]]; then
    export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
fi

# 启用 k8s 命令自动补全
# source <(kubectl completion zsh)

# 启用 az-cli 命令自动补全
autoload -U +X bashcompinit && bashcompinit
if [[ "$_zshrc_os" == "Darwin" ]]; then
    source /opt/homebrew/etc/bash_completion.d/az
else
    source /home/linuxbrew/.linuxbrew/etc/bash_completion.d/az
fi
_zshrc_mark "az completion"

# enable docker buildkit
export DOCKER_BUILDKIT=1

export PATH="$HOME/.local/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
_zshrc_mark "bun completion"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.zsh_scripts:$PATH"

# 引入 Claude Code 环境变量
if [[ -f ~/.claude/user.env ]]; then
    source ~/.claude/user.env
else
    echo "[warn] ~/.claude/user.env not found" >&2
fi
_zshrc_mark "claude user.env"

# User-facing functions are scripts in ~/.zsh_scripts/ (already on PATH):
#   is_work, dl_with_backup, cc_proxy, cc_clean, cc_sync,
#   sync, cc_remote, cc_remote_stop, screen-builtin
# update_zshrc is inline (not a script) so a fresh install with an empty
# ~/.zsh_scripts/ can still bootstrap itself. Uses dl_with_backup when
# available, falls back to plain overwrite otherwise.
update_zshrc() {
    local raw_base="https://raw.githubusercontent.com/dianshu/config/main"
    local _dl
    if command -v dl_with_backup >/dev/null 2>&1; then
        _dl() { dl_with_backup "$1" "$2" }
    else
        _dl() {
            mkdir -p "$(dirname "$2")"
            curl -fsSL -o "$2" "$1" && echo "  OK ${2/$HOME/~}" || { echo "  FAILED ${2/$HOME/~}"; return 1 }
        }
    fi

    echo "=== Updating .zshrc ==="
    _dl "$raw_base/zsh/.zshrc" "$HOME/.zshrc"

    local tree_json
    tree_json="$(curl -fsSL "https://api.github.com/repos/dianshu/config/git/trees/main?recursive=1")"
    if [[ -z "$tree_json" ]]; then
        echo "  ERROR: Failed to fetch repo tree from GitHub API"
        unfunction _dl
        return 1
    fi

    echo "\n=== Syncing zsh/scripts/ ==="
    mkdir -p "$HOME/.zsh_scripts"
    local file_path rel_path
    echo "$tree_json" | jq -r '.tree[] | select((.path | startswith("zsh/scripts/")) and .type == "blob") | .path' \
    | while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        rel_path="${file_path#zsh/scripts/}"
        _dl "$raw_base/$file_path" "$HOME/.zsh_scripts/$rel_path" && chmod +x "$HOME/.zsh_scripts/$rel_path"
    done

    echo "\n=== Syncing zsh/*.zsh ==="
    mkdir -p "$HOME/.zsh"
    echo "$tree_json" | jq -r '.tree[] | select((.path | test("^zsh/[^/]+\\.zsh$")) and .type == "blob") | .path' \
    | while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        rel_path="${file_path#zsh/}"
        _dl "$raw_base/$file_path" "$HOME/.zsh/$rel_path"
    done

    unfunction _dl
    echo "\n=== update_zshrc complete ==="
    echo "Run 'source ~/.zshrc' to reload."
}

: ${CC_REMOTE_PORT:=3006}
_zshrc_mark "functions"

# === 启动性能日志（结束）===
{
    local total=$(( (EPOCHREALTIME - _zshrc_start) * 1000 ))
    local label="[OK]  "
    (( total > 500 )) && label="[SLOW]"
    print "$label $(strftime '%F %T' $epochtime[1]) total=${total}ms PID=$$" >> $_zshrc_log
    for m in "${_zshrc_marks[@]}"; do
        print "$m" >> $_zshrc_log
    done
    print "" >> $_zshrc_log
} always {
    unset _zshrc_start _zshrc_last _zshrc_log _zshrc_marks
    unfunction _zshrc_mark 2>/dev/null
}

# BEGIN HarmonyOS MANAGED BLOCK
export HARMONYOS_CLI_HOME="$HOME/.harmonyos-cli"
export DEVECO_SDK_HOME="$HARMONYOS_CLI_HOME/sdk"
export PATH="$HARMONYOS_CLI_HOME/bin:$PATH"
export PATH="$DEVECO_SDK_HOME/default/openharmony/toolchains:$PATH"
# END HarmonyOS MANAGED BLOCK

# BEGIN Agency MANAGED BLOCK
if [[ ":${PATH}:" != *":$HOME/.config/agency/CurrentVersion:"* ]]; then
    export PATH="$HOME/.config/agency/CurrentVersion:${PATH}"
fi
# END Agency MANAGED BLOCK

# Disable zsh end-of-line mark (the trailing %)
PROMPT_EOL_MARK=""
