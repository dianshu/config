#!/usr/bin/env bash
# Keep the `agency mcp mail` HTTP server's Entra access token fresh.
#
# Why: the mail MCP uses local Entra auth (token TTL ~60min) and only
# refreshes lazily on the next request. After idle periods the next
# Claude Code call hits an expired token and fails. We poke the server
# every N minutes via cron so the refresh happens before any user-visible
# call. Failures are pushed via wxpusher (CC_WXPUSHER_SPT in
# ~/.claude/user.env) so they are noticed.

set -uo pipefail

PORT="${MAIL_MCP_PORT:-30970}"
URL="http://127.0.0.1:${PORT}/"
LOG_DIR="${HOME}/.local/state"
LOG_FILE="${LOG_DIR}/mail_mcp_keepalive.log"
mkdir -p "$LOG_DIR"

[[ -f "${HOME}/.claude/user.env" ]] && source "${HOME}/.claude/user.env"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

notify() {
    local title="$1" content="$2"
    [[ -z "${CC_WXPUSHER_SPT:-}" ]] && return 0
    local body
    body=$(python3 -c "import json,sys;print(json.dumps({'content':sys.argv[1],'summary':sys.argv[2],'contentType':1,'spt':sys.argv[3]}))" "$content" "$title" "$CC_WXPUSHER_SPT")
    curl -s --max-time 10 -X POST "https://wxpusher.zjiecode.com/api/send/message/simple-push" \
        -H "Content-Type: application/json" \
        -d "$body" >/dev/null 2>&1 || true
}

body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

do_request() {
    curl -sS -o "$body_file" -w '%{http_code}' \
        --max-time 20 --connect-timeout 10 \
        -X POST "$URL" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"keepalive","version":"1"}}}' 2>/dev/null
}

http_code=$(do_request) || http_code="curl_error"
if [[ "$http_code" != "200" ]]; then
    sleep 2
    http_code=$(do_request) || http_code="curl_error"
fi

if [[ "$http_code" == "200" ]]; then
    echo "$(ts) ok" >> "$LOG_FILE"
    exit 0
fi

snippet=$(head -c 300 "$body_file" 2>/dev/null)
msg="mail MCP keepalive failed
host: $(hostname)
url: $URL
http: $http_code
body: ${snippet:-<empty>}"
echo "$(ts) FAIL http=$http_code body=${snippet}" >> "$LOG_FILE"
notify "[mail-mcp] keepalive failed ($http_code)" "$msg"
exit 1
