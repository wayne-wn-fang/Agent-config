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

HOME="$TMP_HOME" "$REPO_DIR/setup-global-agent-env.sh" >/dev/null

if [ "$(readlink "$TARGET")" != "$EXPECTED" ]; then
    echo "Expected repeated setup to keep symlink target unchanged"
    exit 1
fi
