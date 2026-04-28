#!/bin/bash
set -euo pipefail

# Link global agent rules from this repository into the local Codex config.
# Usage: bash ~/Agent-config/setup-global-agent-env.sh

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE="$SCRIPT_DIR/global/codex/AGENTS.md"
CODEX_DIR="$HOME/.codex"
CODEX_TARGET="$CODEX_DIR/AGENTS.md"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_RULES_TARGET="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_SETTINGS_SOURCE="$SCRIPT_DIR/claude/settings.json"
CLAUDE_SETTINGS_TARGET="$CLAUDE_DIR/settings.json"
CLAUDE_HOOKS_DIR="$CLAUDE_DIR/hooks"
CLAUDE_HOOK_SOURCE="$SCRIPT_DIR/claude/validate-commit.sh"
CLAUDE_HOOK_TARGET="$CLAUDE_HOOKS_DIR/validate-commit.sh"

if [ ! -f "$SOURCE" ]; then
    echo "Error: missing source file: $SOURCE"
    exit 1
fi

if [ ! -f "$CLAUDE_SETTINGS_SOURCE" ]; then
    echo "Error: missing Claude settings file: $CLAUDE_SETTINGS_SOURCE"
    exit 1
fi

if [ ! -f "$CLAUDE_HOOK_SOURCE" ]; then
    echo "Error: missing Claude hook file: $CLAUDE_HOOK_SOURCE"
    exit 1
fi

mkdir -p "$CODEX_DIR"

if [ -e "$CODEX_TARGET" ] && [ ! -L "$CODEX_TARGET" ]; then
    cp "$CODEX_TARGET" "$CODEX_TARGET.bak"
    echo "Backed up existing AGENTS.md to $CODEX_TARGET.bak"
fi

ln -sfn "$SOURCE" "$CODEX_TARGET"
echo "Linked $CODEX_TARGET -> $SOURCE"

# Link global Rust rules for Copilot (user-level .instructions.md)
COPILOT_PROMPTS_DIR="$HOME/.vscode-server/data/User/prompts"
COPILOT_TARGET="$COPILOT_PROMPTS_DIR/rust-rules.instructions.md"

mkdir -p "$COPILOT_PROMPTS_DIR"

if [ -e "$COPILOT_TARGET" ] && [ ! -L "$COPILOT_TARGET" ]; then
    cp "$COPILOT_TARGET" "$COPILOT_TARGET.bak"
    echo "Backed up existing rust-rules.instructions.md to $COPILOT_TARGET.bak"
fi

ln -sfn "$SOURCE" "$COPILOT_TARGET"
echo "Linked $COPILOT_TARGET -> $SOURCE"

mkdir -p "$CLAUDE_HOOKS_DIR"

if [ -e "$CLAUDE_RULES_TARGET" ] && [ ! -L "$CLAUDE_RULES_TARGET" ]; then
    cp "$CLAUDE_RULES_TARGET" "$CLAUDE_RULES_TARGET.bak"
    echo "Backed up existing CLAUDE.md to $CLAUDE_RULES_TARGET.bak"
fi

ln -sfn "$SOURCE" "$CLAUDE_RULES_TARGET"
echo "Linked $CLAUDE_RULES_TARGET -> $SOURCE"

if [ -e "$CLAUDE_SETTINGS_TARGET" ] && [ ! -L "$CLAUDE_SETTINGS_TARGET" ]; then
    cp "$CLAUDE_SETTINGS_TARGET" "$CLAUDE_SETTINGS_TARGET.bak"
    echo "Backed up existing settings.json to $CLAUDE_SETTINGS_TARGET.bak"
fi

ln -sfn "$CLAUDE_SETTINGS_SOURCE" "$CLAUDE_SETTINGS_TARGET"
echo "Linked $CLAUDE_SETTINGS_TARGET -> $CLAUDE_SETTINGS_SOURCE"

if [ -e "$CLAUDE_HOOK_TARGET" ] && [ ! -L "$CLAUDE_HOOK_TARGET" ]; then
    cp "$CLAUDE_HOOK_TARGET" "$CLAUDE_HOOK_TARGET.bak"
    echo "Backed up existing validate-commit.sh to $CLAUDE_HOOK_TARGET.bak"
fi

ln -sfn "$CLAUDE_HOOK_SOURCE" "$CLAUDE_HOOK_TARGET"
chmod +x "$CLAUDE_HOOK_SOURCE"
echo "Linked $CLAUDE_HOOK_TARGET -> $CLAUDE_HOOK_SOURCE"
