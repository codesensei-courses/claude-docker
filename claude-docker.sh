#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-folder>" >&2
    echo "Example: $0 ~/dev/my_website" >&2
    exit 1
fi

PROJECT_ABS="$(realpath "$1")"
PROJECT_NAME="$(basename "$PROJECT_ABS")"

# Locate installed assets and state (XDG Base Directory compliant)
CLAUDE_DOCKER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-docker"
IMAGE_DIR="$CLAUDE_DOCKER_DATA/image"
STATE_DIR="$CLAUDE_DOCKER_DATA/state"

# Build the image if it doesn't exist yet
if ! docker image inspect claude-docker:latest &>/dev/null; then
    echo "Docker image 'claude-docker:latest' not found."
    read -rp "Build it now? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        BUILD_ARGS=(--build-arg UID="$(id -u)")
        if [[ -n "${LANG:-}" ]]; then
            read -rp "Match host locale '$LANG' in the image? [Y/n] " loc_answer
            if [[ ! "$loc_answer" =~ ^[Nn]$ ]]; then
                BUILD_ARGS+=(--build-arg LOCALE="$LANG")
            fi
        fi
        docker build "${BUILD_ARGS[@]}" -t claude-docker:latest "$IMAGE_DIR"
        echo
        echo "Tip: customize your image by editing"
        echo "    $IMAGE_DIR/build-extras.sh"
        echo "then remove the image (docker image rm claude-docker:latest) and"
        echo "re-run this command to rebuild."
        echo
    else
        echo "Aborted." >&2
        exit 1
    fi
fi

# Ensure host state files exist
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/credentials.json"
chmod 600 "$STATE_DIR/credentials.json"
[ -e "$STATE_DIR/claude.json" ] || echo '{}' > "$STATE_DIR/claude.json"

# Attach to existing session or start a new container
docker exec -it claude-docker tmux attach 2>/dev/null || \
docker run -it --rm  \
    --mount type=bind,source="$PROJECT_ABS",destination="/home/codesensei/$PROJECT_NAME" \
    -v "$STATE_DIR/credentials.json":/home/codesensei/.claude/.credentials.json \
    -v "$STATE_DIR/claude.json":/home/codesensei/.claude.json \
    -w "/home/codesensei/$PROJECT_NAME" \
    claude-docker \
    tmux new-session claude
