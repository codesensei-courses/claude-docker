#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-folder>" >&2
    echo "Example: $0 ~/dev/my_website" >&2
    exit 1
fi

PROJECT_ABS="$(realpath "$1")"
PROJECT_NAME="$(basename "$PROJECT_ABS")"

# Ensure host state files exist (same as make claude-state)
mkdir -p ~/.claude-docker
touch ~/.claude-docker/.credentials.json ~/.claude-docker/.claude.json
chmod 600 ~/.claude-docker/.credentials.json

# Attach to existing session or start a new container
docker exec -it live-courses tmux attach 2>/dev/null || \
docker run -it --rm  \
    --mount type=bind,source="$PROJECT_ABS",destination="/home/codesensei/$PROJECT_NAME" \
    -v ~/.claude-docker/.credentials.json:/home/codesensei/.claude/.credentials.json \
    -v ~/.claude-docker/.claude.json:/home/codesensei/.claude.json \
    live-courses \
    tmux new-session claude
