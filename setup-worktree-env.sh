#!/bin/bash

# =================================================================
# 腳本名稱：setup-worktree-env.sh
# 功    能：自動建立 AI 設定連結並設定 Git 全域/本地忽略
# 使用方式：進到新 worktree 目錄後執行: bash ~/Agent-config/setup-worktree-env.sh
# =================================================================

# 取得目前的 Agent-config 絕對路徑
CONFIG_BASE="$HOME/Agent-config/fdc-ota"
TARGET_DIR=$(pwd)

echo "🚀 開始為 $TARGET_DIR 建立 AI 開發環境..."

# 1. 建立軟連結 (強制覆蓋舊連結，且路徑末尾不加斜線以防 Git 誤判)
ln -sf "$CONFIG_BASE/AGENTS.md" ./AGENTS.md
ln -sf "$CONFIG_BASE/AGENTS.md" ./CLAUDE.md
ln -sfn "$CONFIG_BASE/docs" ./docs

echo "🔗 軟連結建立完成 (AGENTS.md, CLAUDE.md -> AGENTS.md, docs)"

# 2. 設定 Git 全域忽略 (Global Ignore)
GLOBAL_IGNORE="$HOME/.gitignore_global"
git config --global core.excludesfile "$GLOBAL_IGNORE"

# 定義要忽略的項目
IGNORE_ITEMS=("AGENTS.md" "CLAUDE.md" "docs" "docs/")

for item in "${IGNORE_ITEMS[@]}"; do
    if ! grep -qFx "$item" "$GLOBAL_IGNORE" 2>/dev/null; then
        echo "$item" >> "$GLOBAL_IGNORE"
    fi
done
echo "👻 Git 全域忽略設定已更新 (~/.gitignore_global)"

# 3. 針對 Worktree 的特殊本地排除 (解決 Not a directory 報錯)
if [ -f ".git" ] || [ -d ".git" ]; then
    # 自動抓取 worktree 真正的 git 管理目錄
    GIT_REAL_DIR=$(git rev-parse --git-dir)
    mkdir -p "$GIT_REAL_DIR/info"
    for item in "${IGNORE_ITEMS[@]}"; do
        if ! grep -qFx "$item" "$GIT_REAL_DIR/info/exclude" 2>/dev/null; then
            echo "$item" >> "$GIT_REAL_DIR/info/exclude"
        fi
    done
    echo "🔒 Worktree 本地排除已設定 ($GIT_REAL_DIR/info/exclude)"
fi

# 4. 將 ~/.claude/settings.json 替換為指向 Agent-config 的軟連結
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
AGENT_SETTINGS="$HOME/Agent-config/claude/settings.json"

if [ -f "$CLAUDE_SETTINGS" ] && [ ! -L "$CLAUDE_SETTINGS" ]; then
    cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.bak"
    echo "📦 已備份原有 settings.json -> ${CLAUDE_SETTINGS}.bak"
fi

ln -sf "$AGENT_SETTINGS" "$CLAUDE_SETTINGS"
echo "🔗 Claude Code settings.json 已連結 ($CLAUDE_SETTINGS -> $AGENT_SETTINGS)"

# 5. 將 validate-commit.sh 連結到 ~/.claude/hooks/
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"
ln -sf "$HOME/Agent-config/claude/validate-commit.sh" "$HOOKS_DIR/validate-commit.sh"
chmod +x "$HOME/Agent-config/claude/validate-commit.sh"
echo "🔗 validate-commit.sh 已連結 ($HOOKS_DIR/validate-commit.sh)"

# 6. 將 pr-review.md 連結到 ~/.claude/commands/
COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$COMMANDS_DIR"
ln -sf "$HOME/Agent-config/claude/pr-review.md" "$COMMANDS_DIR/pr-review.md"
echo "🔗 pr-review.md 已連結 ($COMMANDS_DIR/pr-review.md)"

echo "✅ 環境同步成功！執行 git status 檢查看看吧。"
