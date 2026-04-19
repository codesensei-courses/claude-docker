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
        # Detect host timezone. On both Linux and macOS /etc/localtime is a
        # symlink into a zoneinfo tree; the IANA name is whatever comes after
        # "zoneinfo/" (e.g. /usr/share/zoneinfo/Europe/Amsterdam on Linux,
        # /var/db/timezone/zoneinfo/Europe/Amsterdam on macOS).
        HOST_TZ=""
        if tz_link="$(readlink /etc/localtime 2>/dev/null)" && [[ "$tz_link" == *zoneinfo/* ]]; then
            HOST_TZ="${tz_link##*zoneinfo/}"
        elif [[ -r /etc/timezone ]]; then
            HOST_TZ="$(< /etc/timezone)"
        fi
        if [[ -n "$HOST_TZ" ]]; then
            read -rp "Match host timezone '$HOST_TZ' in the image? [Y/n] " tz_answer
            if [[ ! "$tz_answer" =~ ^[Nn]$ ]]; then
                BUILD_ARGS+=(--build-arg TZ="$HOST_TZ")
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

# ── User-configured extra mounts ─────────────────────────────────────────────
# Two mechanisms, both optional:
#   1. $CLAUDE_DOCKER_DATA/mounts.conf — one "src:dst[:ro]" spec per line.
#      Lines starting with # and blank lines are ignored. "~" in src expands
#      to $HOME. Missing sources are warned about and skipped.
#   2. $CLAUDE_DOCKER_DATA/home/       — anything here is bind-mounted at the
#      matching path under /home/codesensei/ (e.g. home/.gitconfig →
#      /home/codesensei/.gitconfig). Dotfiles included.
EXTRA_MOUNTS=()

MOUNTS_CONF="$CLAUDE_DOCKER_DATA/mounts.conf"
if [ -r "$MOUNTS_CONF" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue

        IFS=: read -r src dst opt <<< "$line"
        src="${src/#\~/$HOME}"

        if [ -z "$src" ] || [ -z "$dst" ]; then
            echo "Warning: skipping malformed mounts.conf line: $line" >&2
            continue
        fi
        if [ ! -e "$src" ]; then
            echo "Warning: mount source does not exist, skipping: $src" >&2
            continue
        fi

        spec="$src:$dst"
        echo "Detected mount: $src -> $dst"
        [ -n "${opt:-}" ] && spec="$spec:$opt"

        EXTRA_MOUNTS+=(-v "$spec")
    done < "$MOUNTS_CONF"
fi

HOME_OVERLAY="$CLAUDE_DOCKER_DATA/home"
if [ -d "$HOME_OVERLAY" ]; then
    shopt -s dotglob nullglob
    for entry in "$HOME_OVERLAY"/*; do
        name="$(basename "$entry")"
        EXTRA_MOUNTS+=(-v "$entry:/home/codesensei/$name")
    done
    shopt -u dotglob nullglob
fi

# Attach to existing session or start a new container
docker exec -it claude-docker tmux attach 2>/dev/null || \
docker run -it --rm  \
    --mount type=bind,source="$PROJECT_ABS",destination="/home/codesensei/$PROJECT_NAME" \
    -v "$STATE_DIR/credentials.json":/home/codesensei/.claude/.credentials.json \
    -v "$STATE_DIR/claude.json":/home/codesensei/.claude.json \
    ${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"} \
    -w "/home/codesensei/$PROJECT_NAME" \
    claude-docker \
    tmux new-session claude
