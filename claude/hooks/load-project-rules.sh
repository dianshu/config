#!/usr/bin/env bash
# SessionStart hook: load ./.claude/rules/*.md from cwd into context.

set -u

emit_empty() {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}\n'
  exit 0
}

rules_dir="./.claude/rules"
[ -d "$rules_dir" ] || emit_empty

shopt -s nullglob
files=("$rules_dir"/*.md)
shopt -u nullglob
[ ${#files[@]} -gt 0 ] || emit_empty

IFS=$'\n' sorted=($(printf '%s\n' "${files[@]}" | sort))
unset IFS

context="Project-local rules from ./.claude/rules/ (loaded by SessionStart hook):"$'\n'
for f in "${sorted[@]}"; do
  body=$(cat "$f" 2>/dev/null) || continue
  context+=$'\n'"## $f"$'\n\n'"$body"$'\n'
done

python3 -c '
import json, sys
ctx = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
' <<< "$context"
