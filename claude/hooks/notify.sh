#!/bin/bash
source ~/.claude/user.env 2>/dev/null

[[ -z "$CC_WXPUSHER_SPT" ]] && exit 0

payload=$(cat)
message=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('message',''))")
ntype=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('notification_type',''))")
cwd=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('cwd',''))")
sid=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('session_id',''))")

project=$(basename "$cwd")
sid_short="${sid: -5}"
ts=$(date +%H:%M)

summary="[${project}·${sid_short}] ${message}"
content="# ${message}\n\n- **项目**: ${project}\n- **会话**: ${sid_short}\n- **类型**: ${ntype}\n- **时间**: ${ts}"

body=$(python3 -c "import json,sys;print(json.dumps({'content':sys.argv[1],'summary':sys.argv[2],'contentType':3,'spt':sys.argv[3]}))" "$(printf "$content")" "$summary" "$CC_WXPUSHER_SPT")

curl -s -X POST "https://wxpusher.zjiecode.com/api/send/message/simple-push" \
    -H "Content-Type: application/json" \
    -d "$body" &>/dev/null &

exit 0
