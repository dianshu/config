#!/bin/bash
source ~/.claude/user.env 2>/dev/null

[[ -z "$CC_WXPUSHER_SPT" ]] && exit 0

payload=$(cat)
message=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('message',''))")
ntype=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('notification_type',''))")
cwd=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('cwd',''))")
transcript=$(echo "$payload" | python3 -c "import json,sys;print(json.load(sys.stdin).get('transcript_path',''))")

project=$(basename "$cwd")
ts=$(date +%H:%M)

# Recap model — override via CC_NOTIFY_RECAP_MODEL in user.env. Empty = skip recap.
recap_model="${CC_NOTIFY_RECAP_MODEL:-claude-haiku-4.5}"

(
    recap=""
    last_user=""
    last_assistant=""

    if [[ -n "$transcript" && -f "$transcript" ]]; then
        # Extract last user message and last assistant text from transcript.
        last_user=$(tail -n 200 "$transcript" 2>/dev/null | python3 -c "
import json,sys
last=''
for line in sys.stdin:
    try: obj=json.loads(line)
    except: continue
    msg=obj.get('message') or {}
    if (msg.get('role') or obj.get('type'))!='user': continue
    content=msg.get('content'); text=''
    if isinstance(content,list):
        parts=[c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text' and c.get('text')]
        text='\n'.join(parts).strip()
    elif isinstance(content,str):
        text=content.strip()
    if text and not text.startswith('<') and 'tool_result' not in text and 'system-reminder' not in text:
        last=text
print(last[:600])
" 2>/dev/null)
        last_assistant=$(tail -n 200 "$transcript" 2>/dev/null | python3 -c "
import json,sys
last=''
for line in sys.stdin:
    try: obj=json.loads(line)
    except: continue
    msg=obj.get('message') or {}
    if (msg.get('role') or obj.get('type'))!='assistant': continue
    content=msg.get('content'); text=''
    if isinstance(content,list):
        parts=[c.get('text','') for c in content if isinstance(c,dict) and c.get('type')=='text' and c.get('text')]
        text='\n'.join(parts).strip()
    elif isinstance(content,str):
        text=content.strip()
    if text: last=text
print(last[:600])
" 2>/dev/null)

        if [[ -n "$recap_model" && -n "$ANTHROPIC_BASE_URL" && -n "$ANTHROPIC_AUTH_TOKEN" ]]; then
            recent=$(tail -n 60 "$transcript" 2>/dev/null \
                | python3 -c "
import json,sys
out=[]
for line in sys.stdin:
    try: obj=json.loads(line)
    except: continue
    msg=obj.get('message') or {}
    role=msg.get('role') or obj.get('type') or ''
    content=msg.get('content')
    if isinstance(content,list):
        for c in content:
            t=c.get('text') if isinstance(c,dict) else None
            if t: out.append(f'[{role}] {t}')
    elif isinstance(content,str):
        out.append(f'[{role}] {content}')
print('\n'.join(out)[-4000:])
" 2>/dev/null)
            if [[ -n "$recent" ]]; then
                req=$(M="$recap_model" R="$recent" python3 -c "
import json,os
prompt='以下是对话最近内容。用最多12个汉字概括对话当前状态（在做什么/在等什么）。只输出概括本身，不要标点结尾，不要前缀。\n\n'+os.environ['R']
print(json.dumps({'model':os.environ['M'],'max_tokens':60,'messages':[{'role':'user','content':prompt}]}))
")
                short_recap=$(curl -sS --max-time 20 -X POST "$ANTHROPIC_BASE_URL/v1/messages" \
                    -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" \
                    -H "authorization: Bearer $ANTHROPIC_AUTH_TOKEN" \
                    -H "anthropic-version: 2023-06-01" \
                    -H "content-type: application/json" \
                    -d "$req" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); c=d.get('content')
    if isinstance(c,list) and c and isinstance(c[0],dict):
        print(c[0].get('text','').strip()[:200])
except: pass
" 2>/dev/null)
            fi
        fi
    fi

    [[ -z "$short_recap" ]] && short_recap="$message"
    short_recap=$(python3 -c "import sys;print(sys.argv[1].strip().rstrip('。.;,，')[:14])" "$short_recap")

    summary="[${project}] ${short_recap}"

    content="**最近用户消息**

${last_user:-_(无)_}

**最近助手输出**

${last_assistant:-_(无)_}"

    body=$(python3 -c "import json,sys;print(json.dumps({'content':sys.argv[1],'summary':sys.argv[2],'contentType':3,'spt':sys.argv[3]}))" "$content" "$summary" "$CC_WXPUSHER_SPT")

    curl -s --max-time 5 -X POST "https://wxpusher.zjiecode.com/api/send/message/simple-push" \
        -H "Content-Type: application/json" \
        -d "$body" &>/dev/null
) </dev/null &>/dev/null &
disown

exit 0
