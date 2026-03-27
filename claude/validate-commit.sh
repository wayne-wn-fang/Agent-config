#!/bin/bash

# PreToolUse hooks receive JSON via stdin.
# Extract the bash command from the tool input.
TOOL_INPUT=$(cat)
COMMAND=$(echo "$TOOL_INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null)

# Only proceed if this command contains a git commit
if ! echo "$COMMAND" | grep -q 'git commit'; then
    exit 0
fi

# Extract the commit message from the command.
# Handle two formats:
#   1. -m "single line message"
#   2. -m "$(cat <<'EOF'\nmulti\nline\nEOF\n)"  (heredoc)
COMMIT_MSG=$(echo "$COMMAND" | python3 -c "
import sys, re

cmd = sys.stdin.read()

# Try heredoc format first: content between <<'EOF' and EOF (or <<EOF and EOF)
m = re.search(r\"<<'?EOF'?\n(.*?)\nEOF\", cmd, re.DOTALL)
if m:
    print(m.group(1).strip())
    sys.exit(0)

# Try -m \"...\" format (single or multiline inside quotes after -m)
m = re.search(r'-m\s+\"(.*?)\"(?:\s|$)', cmd, re.DOTALL)
if m:
    print(m.group(1).strip())
    sys.exit(0)

# Try -m '...' format
m = re.search(r\"-m\s+'(.*?)'(?:\s|$)\", cmd, re.DOTALL)
if m:
    print(m.group(1).strip())
    sys.exit(0)
" 2>/dev/null)

if [ -z "$COMMIT_MSG" ]; then
    echo "⚠️  無法解析 commit message，跳過格式驗證"
    exit 0
fi

ERRORS=()

# 取得 Header（第一行）
HEADER=$(echo "$COMMIT_MSG" | head -n 1)

# 規則 1：Header 必須包含 Ticket ID（格式：FDC-123:）
if ! echo "$HEADER" | grep -qE '^[A-Z]+-[0-9]+: '; then
  ERRORS+=("❌ Header 必須以 Ticket ID 開頭，格式為 FDC-123: Subject")
fi

# 規則 2：Header 不超過 72 字元
HEADER_LEN=${#HEADER}
if [ "$HEADER_LEN" -gt 72 ]; then
  ERRORS+=("❌ Header 超過 72 字元（目前 ${HEADER_LEN} 字元）")
fi

# 規則 3：Subject 不以句號結尾
if echo "$HEADER" | grep -qE '\.$'; then
  ERRORS+=("❌ Subject 不能以句號結尾")
fi

# 規則 4：Subject 首字母大寫
SUBJECT=$(echo "$HEADER" | sed 's/^[A-Z]*-[0-9]*: [a-z]*: //' | sed 's/^[A-Z]*-[0-9]*: //')
FIRST_CHAR=$(echo "$SUBJECT" | cut -c1)
if echo "$FIRST_CHAR" | grep -qE '[a-z]'; then
  ERRORS+=("❌ Subject 首字母必須大寫")
fi

# 規則 5：Header 和 Body 之間必須有空行
SECOND_LINE=$(echo "$COMMIT_MSG" | sed -n '2p')
if [ -n "$SECOND_LINE" ]; then
  ERRORS+=("❌ Header 和 Body 之間必須有一行空行")
fi

# 規則 6：Body 每行不超過 75 字元
LINE_NUM=0
while IFS= read -r line; do
  LINE_NUM=$((LINE_NUM + 1))
  if [ "$LINE_NUM" -le 2 ]; then continue; fi
  if [ ${#line} -gt 75 ]; then
    ERRORS+=("❌ Body 第 ${LINE_NUM} 行超過 75 字元")
  fi
done <<< "$COMMIT_MSG"

# 輸出結果
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "⛔ Commit message 格式不符合規範："
  for err in "${ERRORS[@]}"; do
    echo "  $err"
  done
  echo ""
  echo "📋 正確格式範例："
  echo "  OTAFVT-110: Add parallel update support"
  echo "  （空行）"
  echo "  1. Spawn DDS tasks concurrently"
  echo "  2. UDS/SPI lane waits on conflicts"
  exit 1
fi

echo "✅ Commit message 格式正確"
exit 0
