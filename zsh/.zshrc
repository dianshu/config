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
abbr --quiet -S gbd='git branch --merged | grep --color=auto -v "main" | xargs -L 1 -p git branch -d'
abbr --quiet -S check='git status --porcelain | awk "/.py/ {print \$2}" | xargs -t flake8 --max-line-length=120'
abbr --quiet -S check2='git status --porcelain | awk "/.py/ {print \$2}" | cut -c 24- | xargs -t flake8 --max-line-length=120'
abbr --quiet -S grep='grep --color=auto'
abbr --quiet -S k='kubectl'
abbr --quiet -S dc='docker compose'
abbr --quiet -S d='docker'
abbr --quiet -S cc='claude'

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

export PATH="$HOME/.local/bin:$PATH"
export BROWSER=wslview

# bun completions
[ -s "/home/fei/.bun/_bun" ] && source "/home/fei/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

####################################################################################
#                                     Functions                                    #
####################################################################################
function docker_build() {
    docker build --add-host $(ifconfig eth0 | grep "inet " | awk '{print "host.docker.internal:"$2}') $@
}

cc_proxy() {
    local port="${1:-29427}"
    local settings_file="$HOME/.claude/settings.json"
    local settings_dir="$HOME/.claude"

    # Check if port is in use
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo "Port $port is binded, need to change a port"
        return 1
    fi

    # Create directory if it doesn't exist
    [[ -d "$settings_dir" ]] || mkdir -p "$settings_dir"

    # Update or create settings.json with the new port
    local tmp_file=$(mktemp)
    if [[ -f "$settings_file" ]]; then
        jq --arg port "$port" '.env.ANTHROPIC_BASE_URL = "http://localhost:\($port)" | .env.ANTHROPIC_AUTH_TOKEN = "your-anthropic-auth-token" | .env.CLAUDE_CODE_SKIP_AUTH_LOGIN = "true" | .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
    else
        echo "{\"env\":{\"ANTHROPIC_BASE_URL\":\"http://localhost:$port\",\"ANTHROPIC_AUTH_TOKEN\":\"your-anthropic-auth-token\",\"CLAUDE_CODE_SKIP_AUTH_LOGIN\":\"true\",\"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\":\"1\"}}" | jq . > "$settings_file"
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

model = "gpt-5.3-codex"
model_provider = "local-proxy"

[model_providers.local-proxy]
name = "Local Proxy"
base_url = "http://localhost:$port/v1"
wire_api = "responses"
env_key = "HOME"
EOF
    fi
    echo "Updated $codex_config with port $port"

    # Start the copilot API
    npx --yes @dianshuv/copilot-api@latest start -p "$port" -a "enterprise"
}

function scan_vulns() {
    local dockerfile="Dockerfile"
    local build_dir="."

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
            *)
                echo "Unknown option: $1"
                echo "Usage: scan_vulns [--dockerfile|-f <path>] [--dir|-d <directory>]"
                return 1
                ;;
        esac
    done

    local timestamp=$(date +%Y%m%d%H%M%S)
    local image="test:${timestamp}"

    echo "Authenticating to ACR: aihardware..."
    az acr login --name aihardware || { echo "ACR login failed"; return 1; }

    echo "Building image: ${image}..."
    docker build --no-cache --pull -f "$dockerfile" -t "$image" "$build_dir" || { echo "Docker build failed"; return 1; }

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

cc_remote() {
    # Named pipe to capture hub output while keeping it visible in terminal
    local fifo=$(mktemp -u)
    mkfifo "$fifo"
    local monitor_pid=""

    # Cleanup on exit/interrupt
    trap 'rm -f "$fifo"; [[ -n "$monitor_pid" ]] && kill "$monitor_pid" 2>/dev/null; trap - EXIT INT TERM' EXIT INT TERM

    export CLI_API_TOKEN=$(openssl rand -base64 32)

    # Background monitor: read fifo, wait for trigger string, then launch client
    {
        while IFS= read -r line; do
            if [[ "$line" == *"or scan the QR code to open"* ]]; then
                setsid npx @twsxtd/hapi &
                local client_pid=$!
                sleep 5
                kill -TERM -"$client_pid" 2>/dev/null
                wait "$client_pid" 2>/dev/null
                break
            fi
        done < "$fifo"
    } &
    monitor_pid=$!

    # Run hub in foreground, tee output to fifo for monitor process
    npx @twsxtd/hapi hub --relay 2>&1 | tee "$fifo"
}

cc_clean() {
    rm -rf ~/.claude ~/.claude.json ~/.local/share/claude/
    for dir in ~/repos/*/; do
        rm -rf "$dir/.claude" "$dir/.mcp.json"
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
        echo "  Backed up: ${dest/$HOME/~} -> ${backup/$HOME/~}"
    fi
    if wget -qO "$dest" "$url"; then
        echo "  Downloaded: ${dest/$HOME/~}"
    else
        echo "  FAILED: ${dest/$HOME/~}"
        return 1
    fi
}

cc_sync() {
    # 1. Install or update Claude CLI
    echo "=== Claude CLI ==="
    if command -v claude &>/dev/null; then
        echo "  Found, updating..."
        claude update
    else
        echo "  Not found, installing..."
        curl -fsSL https://claude.ai/install.sh | bash
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
    for skill source in "${(@kv)skill_sources}"; do
        if echo "$installed_skills" | grep -qw "$skill"; then
            echo "  Skill '$skill' already installed"
        else
            echo "  Installing skill '$skill'..."
            npx -y skills add "$source" -g -y
        fi
    done
    echo "  Updating all skills..."
    npx -y skills update

    # 4. Workspace directory
    echo "\n=== Workspace ==="
    mkdir -p "$HOME/repos/general-chat-using-claude-code"
    echo "  Ensured: ~/repos/general-chat-using-claude-code"

    # 5. Marketplaces (add if missing, then update all)
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

    # 6. Plugins (install if missing, update if exists)
    echo "\n=== Plugins ==="
    local plugins_json="$HOME/.claude/plugins/installed_plugins.json"
    local -a plugins=(
        "superpowers@superpowers-marketplace"
        "microsoft-docs@microsoft-docs-marketplace"
        "document-skills@anthropic-agent-skills"
        "code-simplifier@claude-plugins-official"
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

    # 6b. MCP Servers (direct registration for servers not installable as plugins)
    echo "\n=== MCP Servers ==="
    if claude mcp get context7 &>/dev/null; then
        echo "  MCP server 'context7' already configured"
    else
        echo "  Adding MCP server 'context7'..."
        claude mcp add -s user context7 -- npx -y @upstash/context7-mcp
    fi

    # 7. Clean up old backup files (>24h)
    echo "\n=== Cleanup ==="
    local count
    count=$(find "$HOME/.claude" -maxdepth 3 -name '*.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' -mtime +0 -type f -print -delete | wc -l)
    echo "  Deleted $count old backup file(s)"

    echo "\n=== cc_sync complete ==="
}

update_zshrc() {
    echo "=== Updating .zshrc ==="
    dl_with_backup \
        "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/zsh/.zshrc" \
        "$HOME/.zshrc"
    # Clean up old .zshrc backup files (>24h)
    local count
    count=$(find "$HOME" -maxdepth 1 -name '.zshrc.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' -mtime +0 -type f -print -delete | wc -l)
    echo "  Deleted $count old .zshrc backup(s)"
    echo "\n=== update_zshrc complete ==="
    echo "Run 'source ~/.zshrc' to reload."
}
