# === 启动性能日志 ===
zmodload zsh/datetime
typeset -g _zshrc_start=$EPOCHREALTIME
typeset -g _zshrc_last=$EPOCHREALTIME
typeset -g _zshrc_log=~/.zsh_startup.log
typeset -ga _zshrc_marks=()
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

# 每次刷新提示符
setopt prompt_subst

# 设置提示符
PROMPT='❰%{$reset_color%}%{$fg[red]%}[$(TZ="Asia/Shanghai" date +%H:%M)]%{$reset_color%}%F{#41C4C2}%n%{$reset_color%}|%{$fg[yellow]%}%1~%{$reset_color%}%F{#5DC441}$(git branch --show-current 2&> /dev/null | xargs -I branch echo "(branch)")%{$reset_color%}❱
%F{#FC7E00}%#%{$reset_color%} '

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
  '"gdiff"'  '"GDK_SCALE=2 GDK_DPI_SCALE=1.5 smerge --new-window ."'
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
compinit
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
export PATH=/snap:$PATH

# 引入 homebrew 相关环境变量
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
_zshrc_mark "brew shellenv"

# 启用 k8s 命令自动补全
# source <(kubectl completion zsh)

# 启用 az-cli 命令自动补全
autoload -U +X bashcompinit && bashcompinit
source /home/linuxbrew/.linuxbrew/etc/bash_completion.d/az
_zshrc_mark "az completion"

# enable docker buildkit
export DOCKER_BUILDKIT=1

export PATH="$HOME/.local/bin:$PATH"
export BROWSER=wslview

# bun completions
[ -s "/home/fei/.bun/_bun" ] && source "/home/fei/.bun/_bun"
_zshrc_mark "bun completion"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/bin:$PATH"

# 引入 Claude Code 环境变量
if [[ -f ~/.claude/user.env ]]; then
    source ~/.claude/user.env
else
    echo "[warn] ~/.claude/user.env not found" >&2
fi
_zshrc_mark "claude user.env"

####################################################################################
#                                     Functions                                    #
####################################################################################
function docker_build() {
    docker build --add-host $(ifconfig eth0 | grep "inet " | awk '{print "host.docker.internal:"$2}') $@
}

function scan_vulns() {
    local dockerfile="Dockerfile"
    local build_dir="."
    local image=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dockerfile|-f)
                dockerfile="$2"
                shift 2
                ;;
            --dir|-d)
                build_dir="$2"
                shift 2
                ;;
            --image|-i)
                image="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: scan_vulns [--dockerfile|-f <path>] [--dir|-d <directory>] [--image|-i <image>]"
                return 1
                ;;
        esac
    done

    echo "Authenticating to ACR: aihardware..."
    az acr login --name aihardware || { echo "ACR login failed"; return 1; }

    if [[ -z "$image" ]]; then
        local timestamp=$(date +%Y%m%d%H%M%S)
        image="test:${timestamp}"
        echo "Building image: ${image}..."
        docker build --no-cache --pull -f "$dockerfile" -t "$image" "$build_dir" || { echo "Docker build failed"; return 1; }
    else
        echo "Using existing image: ${image}"
    fi

    echo "Scanning image with Trivy..."
    trivy image --quiet --ignore-unfixed --format json --scanners vuln "$image" | jq '.Results[].Vulnerabilities // []'
}

sb_start() {
    local base_dir="$HOME/.sing-box"
    local log_dir="$base_dir/logs"
    local log_file="$log_dir/$(date +%Y%m%d_%H%M%S).log"

    mkdir -p "$log_dir"

    # Start sing-box in background
    sing-box run -c "$base_dir/config.json" > "$log_file" 2>&1 &
    local pid=$!

    # Wait briefly and check if still running
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Failed to start sing-box. Check log: $log_file"
        cat "$log_file"
        return 1
    fi

    # Set proxy env
    export http_proxy="http://127.0.0.1:17890"
    export https_proxy="http://127.0.0.1:17890"
    export all_proxy="socks5://127.0.0.1:17890"
    export no_proxy="localhost,127.0.0.1,::1"

    # Enable Docker daemon proxy
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null << 'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:17890"
Environment="HTTPS_PROXY=http://127.0.0.1:17890"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    echo "sing-box started (PID: $pid)"
    echo "Log: $log_file"
    echo "Proxy ON (shell + Docker daemon)"
}

sb_stop() {
    pkill sing-box
    unset http_proxy https_proxy all_proxy no_proxy

    # Disable Docker daemon proxy
    sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    echo "sing-box stopped, Proxy OFF (shell + Docker daemon)"
}

cc_proxy() {
    local port="${1:-29427}"
    local settings_file="$HOME/.claude/settings.json"
    local settings_dir="$HOME/.claude"

    # Kill any process occupying the port (idempotent)
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo "Port $port is in use, killing occupying process..."
        lsof -ti :"$port" | xargs kill -9 2>/dev/null
        sleep 2
    fi

    # Create directory if it doesn't exist
    [[ -d "$settings_dir" ]] || mkdir -p "$settings_dir"

    # Update or create settings.json with the new port
    local tmp_file=$(mktemp)
    if [[ -f "$settings_file" ]]; then
        jq --arg port "$port" '.env.ANTHROPIC_BASE_URL = "http://localhost:\($port)" | .env.ANTHROPIC_AUTH_TOKEN = "your-anthropic-auth-token" | .env.CLAUDE_CODE_SKIP_AUTH_LOGIN = "true" | .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1" | .env.CLAUDE_CODE_NO_FLICKER = "1"' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
    else
        echo "{\"env\":{\"ANTHROPIC_BASE_URL\":\"http://localhost:$port\",\"ANTHROPIC_AUTH_TOKEN\":\"your-anthropic-auth-token\",\"CLAUDE_CODE_SKIP_AUTH_LOGIN\":\"true\",\"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\":\"1\",\"CLAUDE_CODE_NO_FLICKER\":\"1\"}}" | jq . > "$settings_file"
    fi
    echo "Updated $settings_file with port $port"

    # Update Codex config.toml with the new port
    local codex_config="$HOME/.codex/config.toml"
    if [[ -f "$codex_config" ]]; then
        sed -i "s|base_url = \"http://localhost:[0-9]*/v1\"|base_url = \"http://localhost:$port/v1\"|" "$codex_config"
    else
        mkdir -p "$(dirname "$codex_config")"
        cat > "$codex_config" <<EOF
# Codex CLI configuration

model = "gpt-5.4"
model_provider = "local-proxy"
model_reasoning_effort = "high"

[model_providers.local-proxy]
name = "Local Proxy"
base_url = "http://localhost:$port/v1"
wire_api = "responses"
env_key = "HOME"
EOF
    fi
    echo "Updated $codex_config with port $port"

    # Update Gemini CLI .env with the new port
    local gemini_env="$HOME/.gemini/.env"
    mkdir -p "$HOME/.gemini"
    cat > "$gemini_env" <<EOF
GOOGLE_GEMINI_BASE_URL=http://localhost:$port
GEMINI_API_KEY=dummy
EOF
    echo "Updated $gemini_env with port $port"

    # Start SearXNG container for web search
    local searxng_port=30963
    local searxng_config="$HOME/.config/searxng"

    if curl -sf http://localhost:$searxng_port > /dev/null 2>&1; then
        echo "SearXNG already running on port $searxng_port"
    else
        echo "SearXNG not responding, restarting..."
        docker rm -f searxng > /dev/null 2>&1
        if ! docker run -d -p ${searxng_port}:8080 \
            -v "$searxng_config:/etc/searxng" \
            --restart unless-stopped --name searxng searxng/searxng; then
            echo "Failed to start SearXNG container"
        else
            echo "Waiting for SearXNG to start..."
            local max_wait=30
            local waited=0
            while ! curl -sf http://localhost:$searxng_port > /dev/null 2>&1; do
                sleep 1
                waited=$((waited + 1))
                if [[ $waited -ge $max_wait ]]; then
                    echo "SearXNG failed to start within ${max_wait}s"
                    break
                fi
            done
            if [[ $waited -lt $max_wait ]]; then
                echo "SearXNG started on port $searxng_port"
            fi
        fi
    fi

    # Start the copilot API in a tmux session so it survives terminal close
    tmux kill-session -t cc_proxy 2>/dev/null
    tmux new-session -d -s cc_proxy "npx --yes @dianshuv/copilot-api@latest start -p $port -a enterprise --posthog-key $CC_POSTHOG_KEY"
    echo "copilot-api started in tmux session 'cc_proxy' (port $port)"
    echo "  attach: tmux attach -t cc_proxy"
}

cc_clean() {
    local targets=(~/.claude ~/.local/share/claude ~/.claude.json)
    for t in "${targets[@]}"; do
        [[ -e "$t" || -L "$t" ]] && echo "Removing $t" && rm -rf "$t"
    done
    echo "All Claude Code data cleaned. Run 'claude' to re-authenticate."
}

dl_with_backup() {
    local url="$1" dest="$2"
    local dest_dir
    dest_dir="$(dirname "$dest")"
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
    if [[ -f "$dest" ]]; then
        local backup="${dest}.$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$backup"
        touch "$backup"
        echo "  Backed up: ${dest/$HOME/~} -> ${backup/$HOME/~}"
    fi
    if wget -qO "$dest" "$url"; then
        echo "  Downloaded: ${dest/$HOME/~}"
    else
        echo "  FAILED: ${dest/$HOME/~}"
        return 1
    fi
    # Delete old backups (>24h) of this file
    local base_name
    local deleted_count
    base_name="$(basename "$dest")"
    deleted_count="$(find "$dest_dir" -maxdepth 1 -name "${base_name}.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" -mtime +0 -type f -print -delete | wc -l | tr -d '[:space:]')"
    echo "  Deleted old backups: ${deleted_count}"
}

cc_sync() {
    # 1. Install or update Claude CLI
    echo "=== Claude CLI ==="
    if command -v claude &>/dev/null; then
        echo "  Found, updating..."
        claude update
    else
        echo "  Not found, installing..."
        curl -fsSL -4 https://claude.ai/install.sh | bash
    fi

    # 1b. Install or update Codex CLI
    echo "\n=== Codex CLI ==="
    if command -v codex &>/dev/null; then
        echo "  Found, updating..."
    else
        echo "  Not found, installing..."
    fi
    npm i -y -g @openai/codex@latest

    # 1c. Install or update Agency
    echo "\n=== Agency ==="
    if command -v agency &>/dev/null; then
        agency update
    else
        curl -sSfL https://aka.ms/InstallTool.sh | sh -s agency
    fi

    # 1d. Install or update Gemini CLI
    echo "\n=== Gemini CLI ==="
    if command -v gemini &>/dev/null; then
        echo "  Found, updating..."
    else
        echo "  Not found, installing..."
    fi
    npm i -y -g @google/gemini-cli@latest

    # 1e. Upgrade Homebrew packages
    echo "\n=== Homebrew ==="
    if command -v brew &>/dev/null; then
        brew update && brew upgrade
    else
        echo "  brew not found, skipping"
    fi

    # 1f. Clean Trivy local DB cache
    echo "\n=== Trivy Cache ==="
    if [[ -d "$HOME/.cache/trivy" ]]; then
        echo "  Removing Trivy cache (~/.cache/trivy)..."
        rm -rf "$HOME/.cache/trivy"
        echo "  Done"
    else
        echo "  No cache found, skipping"
    fi

    # 2. Config files (dynamically discover + download all files from claude/ in repo)
    echo "\n=== Config Files ==="
    local raw_base="https://raw.githubusercontent.com/dianshu/config/main"
    local tree_json
    tree_json="$(wget -qO- "https://api.github.com/repos/dianshu/config/git/trees/main?recursive=1")"
    if [[ -z "$tree_json" ]]; then
        echo "  ERROR: Failed to fetch repo tree from GitHub API"
        return 1
    fi

    local files
    files="$(echo "$tree_json" | jq -r '.tree[] | select((.path | startswith("claude/")) and .type == "blob") | .path')"
    if [[ -z "$files" ]]; then
        echo "  ERROR: No files found under claude/ in repo tree"
        return 1
    fi

    local rel_path
    while IFS= read -r file_path; do
        rel_path="${file_path#claude/}"
        dl_with_backup "$raw_base/$file_path" "$HOME/.claude/$rel_path"
        if [[ "$rel_path" == *.sh ]]; then
            chmod +x "$HOME/.claude/$rel_path"
        fi
    done <<< "$files"

    # 2b. Codex config file
    echo "\n=== Codex Config ==="
    dl_with_backup "$raw_base/codex/config.toml" "$HOME/.codex/config.toml"

    # 2c. Gemini CLI config file
    echo "\n=== Gemini Config ==="
    dl_with_backup "$raw_base/gemini/settings.json" "$HOME/.gemini/settings.json"

    # Install BurntToast PowerShell module for Windows toast notifications
    if command -v /mnt/q/Programs/PowerShell/7/pwsh.exe &>/dev/null; then
        /mnt/q/Programs/PowerShell/7/pwsh.exe -NoProfile -Command "
            if (-not (Get-Module -ListAvailable -Name BurntToast)) {
                Install-Module -Name BurntToast -Force -Scope CurrentUser
            }
        " 2>/dev/null
        echo "  BurntToast module ensured"
    fi

    # 3. Skills (find-skills, skill-creator)
    echo "\n=== Skills ==="
    local installed_skills
    installed_skills="$(npx -y skills list -g 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
    typeset -A skill_sources=(
        [find-skills]="vercel-labs/skills@find-skills"
        [skill-creator]="anthropics/skills@skill-creator"
    )
    typeset -A skill_agents=(
        [skill-creator]="claude-code"
    )
    for skill source in "${(@kv)skill_sources}"; do
        if echo "$installed_skills" | grep -qw "$skill"; then
            echo "  Skill '$skill' already installed"
        else
            echo "  Installing skill '$skill'..."
            if [[ -n "${skill_agents[$skill]}" ]]; then
                npx -y skills add "$source" -g -a "${skill_agents[$skill]}" -y
            else
                npx -y skills add "$source" -g -y
            fi
        fi
    done
    echo "  Updating all skills..."
    npx -y skills update

    # 4. Marketplaces (add if missing, then update all)
    echo "\n=== Marketplaces ==="
    local mp_json="$HOME/.claude/plugins/known_marketplaces.json"
    typeset -A marketplaces=(
        [superpowers-marketplace]="obra/superpowers-marketplace"
        [microsoft-docs-marketplace]="microsoftdocs/mcp"
        [anthropic-agent-skills]="anthropics/skills"
    )
    for mp_key mp_repo in "${(@kv)marketplaces}"; do
        if [[ -f "$mp_json" ]] && jq -e --arg k "$mp_key" 'has($k)' "$mp_json" &>/dev/null; then
            echo "  Marketplace '$mp_key' already registered"
        else
            echo "  Adding marketplace '$mp_key' ($mp_repo)..."
            claude plugin marketplace add "$mp_repo"
        fi
    done
    echo "  Updating all marketplaces..."
    claude plugin marketplace update

    # 5. Plugins (install if missing, update if exists)
    echo "\n=== Plugins ==="
    local plugins_json="$HOME/.claude/plugins/installed_plugins.json"
    local -a plugins=(
        "superpowers@superpowers-marketplace"
        "microsoft-docs@microsoft-docs-marketplace"
        "document-skills@anthropic-agent-skills"
        "playground@claude-plugins-official"
    )
    for plugin in "${plugins[@]}"; do
        if [[ -f "$plugins_json" ]] && jq -e --arg p "$plugin" '.plugins | has($p)' "$plugins_json" &>/dev/null; then
            echo "  Plugin '$plugin' exists, updating..."
            claude plugin update "$plugin" -s user
        else
            echo "  Installing plugin '$plugin'..."
            claude plugin install "$plugin" -s user
        fi

        # Ensure plugin is enabled (install doesn't auto-enable)
        claude plugin enable "$plugin" -s user 2>/dev/null
    done

    # 5b. SearXNG config
    echo "\n=== SearXNG Config ==="
    local searxng_config="$HOME/.config/searxng"
    [[ -d "$searxng_config" ]] && sudo chown -R "$(id -u):$(id -g)" "$searxng_config"
    dl_with_backup \
        "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/zsh/searxng-settings.yml" \
        "$searxng_config/settings.yml"

    # 5c. SearXNG Docker image
    echo "\n=== SearXNG Docker Image ==="
    docker pull searxng/searxng

    # 5d. MCP Servers (direct registration for servers not installable as plugins)
    echo "\n=== MCP Servers ==="
    claude mcp remove context7 -s user 2>/dev/null
    claude mcp add context7 -s user -- npx -y @upstash/context7-mcp
    echo "  MCP server 'context7' configured"
    claude mcp remove searxng -s user 2>/dev/null
    claude mcp add searxng -s user -e SEARXNG_URL="http://localhost:30963" -- npx -y mcp-searxng
    echo "  MCP server 'searxng' configured"
    claude mcp remove chrome -s user 2>/dev/null
    claude mcp add chrome -s user -- npx -y chrome-devtools-mcp@latest --browserUrl http://localhost:9222
    echo "  MCP server 'chrome' configured"
    claude mcp remove mail -s user 2>/dev/null
    claude mcp add mail -s user -- agency mcp mail
    claude mcp remove s360 -s user 2>/dev/null
    claude mcp add s360 -s user -- agency mcp s360-breeze
    claude mcp remove teams -s user 2>/dev/null
    claude mcp add teams -s user -- agency mcp teams
    echo "  MCP server 'mail' configured"

    echo "\n=== cc_sync complete ==="
}

update_zshrc() {
    echo "=== Updating .zshrc ==="
    dl_with_backup \
        "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/zsh/.zshrc" \
        "$HOME/.zshrc"
    echo "\n=== update_zshrc complete ==="
    echo "Run 'source ~/.zshrc' to reload."
}

: ${CC_REMOTE_PORT:=3006}

cc_remote() {
    cc_remote_stop
    npm install -g @dianshuv/hapi
    tmux new-session -d -s cc_remote "hapi hub --tunnel"
    echo "hapi hub started in tmux session 'cc_remote'"
    echo "  attach: tmux attach -t cc_remote"
}

cc_remote_stop() {
    tmux kill-session -t cc_remote 2>/dev/null
    fuser -k "${CC_REMOTE_PORT}/tcp" 2>/dev/null
    echo "cc_remote stopped"
}
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

# BEGIN Agency MANAGED BLOCK
if [[ ":${PATH}:" != *":/home/fei/.config/agency/CurrentVersion:"* ]]; then
    export PATH="/home/fei/.config/agency/CurrentVersion:${PATH}"
fi
# END Agency MANAGED BLOCK
