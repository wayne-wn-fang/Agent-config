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
ln -sf "$CONFIG_BASE/CLAUDE.md" ./CLAUDE.md
ln -sf "$CONFIG_BASE/docs" ./docs

echo "🔗 軟連結建立完成 (AGENTS.md, CLAUDE.md, docs)"

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

echo "✅ 環境同步成功！執行 git status 檢查看看吧。"
