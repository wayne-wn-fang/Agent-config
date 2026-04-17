# remote-ota Agent Config Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `Agent-config` to centrally manage `remote-ota` agent guidance and docs, with a per-worktree setup script that mirrors the existing fdc-ota pattern.

**Architecture:** Create `Agent-config/remote-ota/` holding `AGENTS.md` and `docs/`. Migrate `~/remote-ota/docs/` into `Agent-config`, then replace it with a symlink back. A new `setup-worktree-env-remote-ota.sh` script symlinks all three (AGENTS.md, CLAUDE.md, docs/) into each new remote-ota worktree.

**Tech Stack:** Bash, git, symlinks. No compiled code.

**Spec:** `Agent-config/docs/superpowers/specs/2026-04-17-remote-ota-agent-config-design.md`

---

### Task 1: Create Agent-config/remote-ota/ skeleton

**Files:**
- Create: `Agent-config/remote-ota/AGENTS.md`
- Create: `Agent-config/remote-ota/docs/` (directory, populated in Task 2)

- [ ] **Step 1: Create the remote-ota AGENTS.md**

Create `~/Agent-config/remote-ota/AGENTS.md` with the following content:

```markdown
# AGENTS.md — remote-ota

## Purpose

`remote-ota` is a single-shot Rust tool that triggers and monitors one OTA firmware update
attempt for one FDC vehicle device over AWS IoT Core MQTT. Each invocation connects,
probes the device VIN, launches `remote-updater`, monitors correlated status traffic,
and exits with a deterministic exit code.

This Agent-config directory (`~/Agent-config/remote-ota/`) is the authoritative source
for agent guidance and documentation. Files here are symlinked into every remote-ota
worktree — edit here and all worktrees pick up changes immediately.

---

## Repository Structure

| File | Responsibility |
|------|---------------|
| `src/main.rs` | CLI parsing, MQTT setup, single-shot orchestration, exit-code mapping |
| `src/messages.rs` | Protocol payload building and JSON parsing helpers |
| `src/topics.rs` | MQTT topic construction helpers |

> Note: `src/session.rs` (OTA state machine and timeout handling) exists in a worktree
> branch and will be added to this table once merged to main.

---

## Verification Commands

All three must pass before committing:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

---

## Issue Tracking

When you find a bug, risk, or code smell, append to `ISSUES.md` in the working directory:

```
- [ ] [problem description] (location: filename:line_number)
```

Do not create `ISSUES.md` proactively — only write it when an actual issue is found.

---

## Plans

Store implementation plans under `docs/superpowers/plans/`. One file per plan,
e.g. `docs/superpowers/plans/feature-name.md`.

---

## Key Invariants — Agents Must Not Violate

- **Single-shot:** One invocation performs exactly one OTA attempt and then exits.
  Do not add retry loops.
- **VIN safety:** A VIN mismatch must always exit with code `2`.
  Never relax or bypass this check.
- **AttemptId correlation:** Correlation is strict string equality on the top-level
  `attemptId` field. Never accept a message with a missing or non-matching `attemptId`.
- **Dual-topic publishing:** Probe and launch commands must always be published to both
  the legacy (`{sn}`) and IOV (`{sn}/iov/remote-cmd/sreq/run-cmd/v0`) run-cmd topics.
  Never publish to only one.
- **Exit codes:** `0` = success, `1` = general failure, `2` = VIN mismatch.
  Do not change this mapping.
```

- [ ] **Step 2: Verify the file was created**

```bash
head -5 ~/Agent-config/remote-ota/AGENTS.md
```

Expected: prints the `# AGENTS.md — remote-ota` header.

- [ ] **Step 3: Commit**

```bash
cd ~/Agent-config
git add remote-ota/AGENTS.md
git commit -m "feat: add remote-ota/AGENTS.md with agent guidance"
```

---

### Task 2: Migrate docs from remote-ota to Agent-config

**Files:**
- Create: `Agent-config/remote-ota/docs/` (populated from `~/remote-ota/docs/`)
- Modify: `~/remote-ota/` (git rm docs/, add symlink)

- [ ] **Step 1: Copy docs into Agent-config first (before touching remote-ota git)**

```bash
cp -r ~/remote-ota/docs/ ~/Agent-config/remote-ota/docs/
```

- [ ] **Step 2: Verify the copy**

```bash
ls ~/Agent-config/remote-ota/docs/
```

Expected: `protocol-spec.md  remote-ota.md  superpowers`

- [ ] **Step 3: Commit docs to Agent-config**

```bash
cd ~/Agent-config
git add remote-ota/docs/
git commit -m "feat: add remote-ota/docs migrated from remote-ota repo"
```

- [ ] **Step 4: Remove docs from remote-ota git history**

```bash
cd ~/remote-ota
git rm -r docs/
git commit -m "chore: remove docs (moved to Agent-config)"
```

- [ ] **Step 5: Create symlink in remote-ota main working directory**

```bash
ln -sfn ~/Agent-config/remote-ota/docs ~/remote-ota/docs
```

- [ ] **Step 6: Exclude the symlink from git tracking**

```bash
grep -qFx "docs" ~/remote-ota/.git/info/exclude || echo "docs" >> ~/remote-ota/.git/info/exclude
grep -qFx "docs/" ~/remote-ota/.git/info/exclude || echo "docs/" >> ~/remote-ota/.git/info/exclude
```

- [ ] **Step 7: Verify symlink works**

```bash
cat ~/remote-ota/docs/remote-ota.md | head -3
git -C ~/remote-ota status
```

Expected: first command prints the remote-ota.md header; `git status` shows `docs` is untracked but not staged (ignored by exclude).

---

### Task 3: Create setup-worktree-env-remote-ota.sh

**Files:**
- Create: `Agent-config/setup-worktree-env-remote-ota.sh`

- [ ] **Step 1: Create the setup script**

Create `~/Agent-config/setup-worktree-env-remote-ota.sh` with the following content:

```bash
#!/bin/bash

# =================================================================
# 腳本名稱：setup-worktree-env-remote-ota.sh
# 功    能：為 remote-ota worktree 建立 AI 設定連結並設定 Git 忽略
# 使用方式：進到新 worktree 目錄後執行: bash ~/Agent-config/setup-worktree-env-remote-ota.sh
# =================================================================

CONFIG_BASE="$HOME/Agent-config/remote-ota"
TARGET_DIR=$(pwd)

echo "🚀 開始為 $TARGET_DIR 建立 remote-ota AI 開發環境..."

# --- Safety check: abort if ./docs is a real directory (not a symlink) ---
if [ -d "./docs" ] && [ ! -L "./docs" ]; then
    echo "❌ 錯誤：./docs 是一個實體目錄，非軟連結。"
    echo "   請先手動處理（備份或刪除）再重新執行此腳本。"
    exit 1
fi

# 1. 建立軟連結
ln -sf "$CONFIG_BASE/AGENTS.md" ./AGENTS.md
ln -sf "$CONFIG_BASE/AGENTS.md" ./CLAUDE.md
ln -sfn "$CONFIG_BASE/docs" ./docs

echo "🔗 軟連結建立完成 (AGENTS.md, CLAUDE.md -> AGENTS.md, docs)"

# 2. 設定 Git 全域忽略
GLOBAL_IGNORE="$HOME/.gitignore_global"
git config --global core.excludesfile "$GLOBAL_IGNORE"

IGNORE_ITEMS=("AGENTS.md" "CLAUDE.md" "docs" "docs/")

for item in "${IGNORE_ITEMS[@]}"; do
    if ! grep -qFx "$item" "$GLOBAL_IGNORE" 2>/dev/null; then
        echo "$item" >> "$GLOBAL_IGNORE"
    fi
done
echo "👻 Git 全域忽略設定已更新 (~/.gitignore_global)"

# 3. Worktree 本地排除
if [ -f ".git" ] || [ -d ".git" ]; then
    GIT_REAL_DIR=$(git rev-parse --git-dir)
    mkdir -p "$GIT_REAL_DIR/info"
    for item in "${IGNORE_ITEMS[@]}"; do
        if ! grep -qFx "$item" "$GIT_REAL_DIR/info/exclude" 2>/dev/null; then
            echo "$item" >> "$GIT_REAL_DIR/info/exclude"
        fi
    done
    echo "🔒 Worktree 本地排除已設定 ($GIT_REAL_DIR/info/exclude)"
fi

# 4. Claude Code settings.json
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
AGENT_SETTINGS="$HOME/Agent-config/claude/settings.json"

if [ -f "$CLAUDE_SETTINGS" ] && [ ! -L "$CLAUDE_SETTINGS" ]; then
    cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.bak"
    echo "📦 已備份原有 settings.json -> ${CLAUDE_SETTINGS}.bak"
fi

ln -sf "$AGENT_SETTINGS" "$CLAUDE_SETTINGS"
echo "🔗 Claude Code settings.json 已連結 ($CLAUDE_SETTINGS -> $AGENT_SETTINGS)"

# 5. validate-commit.sh hook
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"
ln -sf "$HOME/Agent-config/claude/validate-commit.sh" "$HOOKS_DIR/validate-commit.sh"
chmod +x "$HOME/Agent-config/claude/validate-commit.sh"
echo "🔗 validate-commit.sh 已連結 ($HOOKS_DIR/validate-commit.sh)"

# 6. pr-review.md command
COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$COMMANDS_DIR"
ln -sf "$HOME/Agent-config/claude/pr-review.md" "$COMMANDS_DIR/pr-review.md"
echo "🔗 pr-review.md 已連結 ($COMMANDS_DIR/pr-review.md)"

echo "✅ remote-ota 環境同步成功！執行 git status 檢查看看吧。"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x ~/Agent-config/setup-worktree-env-remote-ota.sh
```

- [ ] **Step 3: Smoke-test the script in a temporary worktree**

```bash
git -C ~/remote-ota worktree add /tmp/test-remote-ota-wt
cd /tmp/test-remote-ota-wt
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
```

Expected output ends with: `✅ remote-ota 環境同步成功！執行 git status 檢查看看吧。`

- [ ] **Step 4: Verify the symlinks and docs in the test worktree**

```bash
ls -la /tmp/test-remote-ota-wt/AGENTS.md /tmp/test-remote-ota-wt/CLAUDE.md /tmp/test-remote-ota-wt/docs
cat /tmp/test-remote-ota-wt/docs/remote-ota.md | head -3
git -C /tmp/test-remote-ota-wt status
```

Expected:
- `AGENTS.md` and `CLAUDE.md` are symlinks pointing to `~/Agent-config/remote-ota/AGENTS.md`
- `docs` is a symlink pointing to `~/Agent-config/remote-ota/docs/`
- `docs/remote-ota.md` prints the file header
- `git status` shows clean (symlinks are excluded)

- [ ] **Step 5: Clean up test worktree**

```bash
git -C ~/remote-ota worktree remove /tmp/test-remote-ota-wt
```

- [ ] **Step 6: Commit**

```bash
cd ~/Agent-config
git add setup-worktree-env-remote-ota.sh
git commit -m "feat: add setup-worktree-env-remote-ota.sh"
```

---

### Task 4: Update Agent-config/CLAUDE.md

**Files:**
- Modify: `Agent-config/CLAUDE.md`

- [ ] **Step 1: Read the current CLAUDE.md to find the right insertion point**

Read `~/Agent-config/CLAUDE.md` and locate the end of the fdc-ota section (around the "Maintenance" section or end of file).

- [ ] **Step 2: Add the remote-ota section**

Insert the following block after the fdc-ota "Maintenance" section, before the end of file:

```markdown
## remote-ota Project

- `remote-ota/AGENTS.md` — Authoritative AI agent entry point for the remote-ota project.
- `remote-ota/docs/` — Architecture, protocol, and development documentation for remote-ota.

### Workflow: Setting Up a New Worktree

When a new remote-ota worktree is created, run from inside that worktree directory:

```bash
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
```

This creates symlinks so the worktree always reads the latest agent config from this repo,
and adds the symlinked names to both `~/.gitignore_global` and the worktree-local
`.git/info/exclude`.
```

- [ ] **Step 3: Verify the update renders correctly**

```bash
grep -n "remote-ota" ~/Agent-config/CLAUDE.md
```

Expected: shows at least 3 lines referencing remote-ota (section header, AGENTS.md, docs/).

- [ ] **Step 4: Commit**

```bash
cd ~/Agent-config
git add CLAUDE.md
git commit -m "docs: add remote-ota section to CLAUDE.md"
```

---

### Task 5: End-to-end verification

- [ ] **Step 1: Confirm Agent-config structure**

```bash
ls ~/Agent-config/remote-ota/
ls ~/Agent-config/remote-ota/docs/
```

Expected:
```
AGENTS.md  docs/
protocol-spec.md  remote-ota.md  superpowers/
```

- [ ] **Step 2: Confirm remote-ota main repo symlink**

```bash
ls -la ~/remote-ota/docs
readlink ~/remote-ota/docs
```

Expected: symlink pointing to `~/Agent-config/remote-ota/docs`.

- [ ] **Step 3: Confirm git status is clean in both repos**

```bash
git -C ~/Agent-config status
git -C ~/remote-ota status
```

Expected: both show clean working tree.

- [ ] **Step 4: Create a final verification worktree**

```bash
git -C ~/remote-ota worktree add /tmp/verify-remote-ota-wt
cd /tmp/verify-remote-ota-wt
bash ~/Agent-config/setup-worktree-env-remote-ota.sh
ls -la AGENTS.md CLAUDE.md docs
cat docs/remote-ota.md | head -3
git status
git -C ~/remote-ota worktree remove /tmp/verify-remote-ota-wt
```

Expected: symlinks present, docs readable, git status clean.
