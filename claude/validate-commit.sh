#!/bin/bash

# 取得 commit message
COMMIT_MSG="$1"
if [ -z "$COMMIT_MSG" ]; then
  # 從 git 暫存區取得
  COMMIT_MSG=$(cat .git/COMMIT_EDITMSG 2>/dev/null)
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
  echo "  FDC-123: App crash when low memory"
  echo "  （空行）"
  echo "  1. Catch null pointer exception"
  echo "  2. Add error handle"
  exit 1  # 非 0 exit code 會讓 Claude Code 中止 commit
fi

echo "✅ Commit message 格式正確"
exit 0
