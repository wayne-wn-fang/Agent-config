#!/bin/bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_HOME=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_HOME"
}
trap cleanup EXIT

mkdir -p "$TMP_HOME/.codex"
printf "existing global agent rules\n" > "$TMP_HOME/.codex/AGENTS.md"

HOME="$TMP_HOME" "$REPO_DIR/setup-global-agent-env.sh" >/dev/null

TARGET="$TMP_HOME/.codex/AGENTS.md"
EXPECTED="$REPO_DIR/global/codex/AGENTS.md"
CLAUDE_DIR="$TMP_HOME/.claude"
CLAUDE_RULES_TARGET="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_RULES_EXPECTED="$REPO_DIR/global/codex/AGENTS.md"
CLAUDE_SETTINGS_TARGET="$CLAUDE_DIR/settings.json"
CLAUDE_SETTINGS_EXPECTED="$REPO_DIR/claude/settings.json"
CLAUDE_HOOK_TARGET="$CLAUDE_DIR/hooks/validate-commit.sh"
CLAUDE_HOOK_EXPECTED="$REPO_DIR/claude/validate-commit.sh"

if [ ! -L "$TARGET" ]; then
    echo "Expected $TARGET to be a symlink"
    exit 1
fi

if [ "$(readlink "$TARGET")" != "$EXPECTED" ]; then
    echo "Expected $TARGET to point to $EXPECTED"
    exit 1
fi

if [ ! -f "$TMP_HOME/.codex/AGENTS.md.bak" ]; then
    echo "Expected original AGENTS.md to be backed up"
    exit 1
fi

if [ ! -L "$CLAUDE_RULES_TARGET" ]; then
    echo "Expected $CLAUDE_RULES_TARGET to be a symlink"
    exit 1
fi

if [ "$(readlink "$CLAUDE_RULES_TARGET")" != "$CLAUDE_RULES_EXPECTED" ]; then
    echo "Expected $CLAUDE_RULES_TARGET to point to $CLAUDE_RULES_EXPECTED"
    exit 1
fi

if [ ! -L "$CLAUDE_SETTINGS_TARGET" ]; then
    echo "Expected $CLAUDE_SETTINGS_TARGET to be a symlink"
    exit 1
fi

if [ "$(readlink "$CLAUDE_SETTINGS_TARGET")" != "$CLAUDE_SETTINGS_EXPECTED" ]; then
    echo "Expected $CLAUDE_SETTINGS_TARGET to point to $CLAUDE_SETTINGS_EXPECTED"
    exit 1
fi

if [ ! -L "$CLAUDE_HOOK_TARGET" ]; then
    echo "Expected $CLAUDE_HOOK_TARGET to be a symlink"
    exit 1
fi

if [ "$(readlink "$CLAUDE_HOOK_TARGET")" != "$CLAUDE_HOOK_EXPECTED" ]; then
    echo "Expected $CLAUDE_HOOK_TARGET to point to $CLAUDE_HOOK_EXPECTED"
    exit 1
fi

HOME="$TMP_HOME" "$REPO_DIR/setup-global-agent-env.sh" >/dev/null

if [ "$(readlink "$TARGET")" != "$EXPECTED" ]; then
    echo "Expected repeated setup to keep symlink target unchanged"
    exit 1
fi

if [ "$(readlink "$CLAUDE_RULES_TARGET")" != "$CLAUDE_RULES_EXPECTED" ]; then
    echo "Expected repeated setup to keep Claude rules symlink target unchanged"
    exit 1
fi

if [ "$(readlink "$CLAUDE_SETTINGS_TARGET")" != "$CLAUDE_SETTINGS_EXPECTED" ]; then
    echo "Expected repeated setup to keep Claude settings symlink target unchanged"
    exit 1
fi

if [ "$(readlink "$CLAUDE_HOOK_TARGET")" != "$CLAUDE_HOOK_EXPECTED" ]; then
    echo "Expected repeated setup to keep Claude hook symlink target unchanged"
    exit 1
fi
