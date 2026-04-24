#!/bin/bash
set -euo pipefail

# Link global agent rules from this repository into the local Codex config.
# Usage: bash ~/Agent-config/setup-global-agent-env.sh

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE="$SCRIPT_DIR/global/codex/AGENTS.md"
TARGET_DIR="$HOME/.codex"
TARGET="$TARGET_DIR/AGENTS.md"

if [ ! -f "$SOURCE" ]; then
    echo "Error: missing source file: $SOURCE"
    exit 1
fi

mkdir -p "$TARGET_DIR"

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    cp "$TARGET" "$TARGET.bak"
    echo "Backed up existing AGENTS.md to $TARGET.bak"
fi

ln -sfn "$SOURCE" "$TARGET"
echo "Linked $TARGET -> $SOURCE"
