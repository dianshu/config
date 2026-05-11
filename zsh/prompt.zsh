# Prompt configuration
#
# Layout:
#   ❰[HH:MM]user|dir(branch)❱
#   ❯
#
# Features:
#   - 时间/git 走 precmd 缓存变量，避免每次提示符 fork 子进程
#   - 目录超过 3 层时截断为 .../parent/cur，否则显示完整路径
#   - 第二行 ❯ 根据上条命令退出码染色（成功橙、失败红）

setopt prompt_subst

autoload -U colors && colors

# vcs_info：用 zsh 内建机制取 git 分支
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '(%b)'

# precmd：每次回车前刷新时间、git、退出码颜色
# 必须先抓 $?——后续 date/vcs_info 会覆盖它
_prompt_precmd() {
    local last=$?
    if (( last == 0 )); then
        _prompt_arrow_color='%F{#00D787}'
    else
        _prompt_arrow_color='%B%F{#FF1744}'
    fi
    _prompt_time=$(TZ="Asia/Shanghai" date +%H:%M)
    vcs_info
}
precmd_functions+=(_prompt_precmd)

PROMPT='❰%{$reset_color%}%F{red}[${_prompt_time}]%{$reset_color%}%F{#41C4C2}%n%{$reset_color%}|%F{yellow}%(4~|.../%2~|%~)%{$reset_color%}%F{#5DC441}${vcs_info_msg_0_}%{$reset_color%}❱
${_prompt_arrow_color}❯%b%{$reset_color%} '
