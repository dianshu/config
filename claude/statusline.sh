#!/bin/bash
# Reads Claude Code status JSON from stdin, outputs a colored status line

input=$(cat)

# 1. Model (green)
model=$(echo "$input" | jq -r '
  if .model | type == "string" then .model
  elif .model.display_name then .model.display_name
  elif .model.id then .model.id
  else empty end // empty')

# 2. Context % (from context_window in stdin JSON)
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_usage=$(echo "$input" | jq -r '
  if .context_window.used_percentage and .context_window.context_window_size then
    (.context_window.used_percentage * .context_window.context_window_size / 100 | floor)
  else empty end')
ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
ctx_detail=""
if [ -n "$ctx_pct" ] && [ -n "$ctx_usage" ] && [ -n "$ctx_total" ]; then
  ctx_usage_k=$(awk "BEGIN { printf \"%.0fk\", $ctx_usage / 1000 }")
  ctx_total_k=$(awk "BEGIN { printf \"%.0fk\", $ctx_total / 1000 }")
  ctx_detail="${ctx_pct}% [${ctx_usage_k}/${ctx_total_k}]"
fi

# 3. Git Branch (magenta)
git_branch=$(git --no-optional-locks branch --show-current 2>/dev/null)
git_display="${git_branch:-no git}"

# 4. Current working dir (yellow)
cwd=$(echo "$input" | jq -r '.cwd // empty')
cwd="${cwd/#$HOME/\~}"

# ANSI color codes
GREEN='\033[38;5;70m'
MAGENTA='\033[38;5;96m'
YELLOW='\033[38;5;178m'
GRAY='\033[38;5;245m'
RESET='\033[0m'

# Build output
output="${RESET}"
[ -n "$model" ] && output="${output}${GREEN}Model: ${model}${RESET}"

if [ -n "$ctx_detail" ]; then
  [ -n "$model" ] && output="${output} ${GRAY}|${RESET} "
  output="${output}Ctx: ${ctx_detail}"
fi

output="${output} ${GRAY}|${RESET} ${MAGENTA}⎇ ${git_display}${RESET}"

if [ -n "$cwd" ]; then
  output="${output} ${GRAY}|${RESET} ${YELLOW}cwd: ${cwd}${RESET}"
fi

echo -e "$output"
