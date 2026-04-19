#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-folder>" >&2
    echo "Example: $0 ~/dev/my_website" >&2
    exit 1
fi

PROJECT_ABS="$(realpath "$1")"
PROJECT_NAME="$(basename "$PROJECT_ABS")"

# Build the image if it doesn't exist yet
if ! docker image inspect claude-docker:latest &>/dev/null; then
    echo "Docker image 'claude-docker:latest' not found."
    read -rp "Build it now? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        docker build --build-arg UID="$(id -u)" -t claude-docker:latest "$SCRIPT_DIR"
    else
        echo "Aborted." >&2
        exit 1
    fi
fi

# Ensure host state files exist (XDG Base Directory compliant)
CLAUDE_DOCKER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-docker"
mkdir -p "$CLAUDE_DOCKER_DATA"
touch "$CLAUDE_DOCKER_DATA/.credentials.json" "$CLAUDE_DOCKER_DATA/.claude.json"
chmod 600 "$CLAUDE_DOCKER_DATA/.credentials.json"

# Attach to existing session or start a new container
docker exec -it claude-docker tmux attach 2>/dev/null || \
docker run -it --rm  \
    --mount type=bind,source="$PROJECT_ABS",destination="/home/codesensei/$PROJECT_NAME" \
    -v "$CLAUDE_DOCKER_DATA/.credentials.json":/home/codesensei/.claude/.credentials.json \
    -v "$CLAUDE_DOCKER_DATA/.claude.json":/home/codesensei/.claude.json \
    -w "/home/codesensei/$PROJECT_NAME" \
    claude-docker \
    tmux new-session claude
