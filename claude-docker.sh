#!/usr/bin/env bash
set -euo pipefail

MODE=claude
CUSTOM_CMD=""
YOLO=0
while getopts ":tbce:y" opt; do
    case "$opt" in
        t)  MODE=tmux ;;
        b)  MODE=bash ;;
        c)  MODE=claude ;;
        e)  MODE=exec; CUSTOM_CMD="$OPTARG" ;;
        y)  YOLO=1 ;;
        :)  echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -ne 1 ]; then
    echo "Usage: $0 [-t|-b|-c|-e <cmd>] [-y] <project-folder>" >&2
    echo "  -t         attach to existing tmux session, or start a new one" >&2
    echo "  -b         start just a bash shell" >&2
    echo "  -c         continue the claude session, or start a new one (default)" >&2
    echo "  -e <cmd>   run a custom command via bash -c (supports &&, ||, pipes)" >&2
    echo "  -y         run claude with --dangerously-skip-permissions (yolo mode)" >&2
    echo "Example: $0 ~/dev/my_website" >&2
    echo "         $0 -e 'npm test && npm run build' ~/dev/my_website" >&2
    exit 1
fi

PROJECT_ABS="$(realpath "$1")"
PROJECT_NAME="$(basename "$PROJECT_ABS")"

# Container name: "claude-docker-<project>-<hash>". The 8-char hash of the
# absolute path disambiguates same-named projects in different locations
# (e.g. ~/dev/foo vs ~/work/foo).
if command -v sha1sum >/dev/null 2>&1; then
    PROJECT_HASH=$(printf '%s' "$PROJECT_ABS" | sha1sum | cut -c1-8)
else
    PROJECT_HASH=$(printf '%s' "$PROJECT_ABS" | shasum | cut -c1-8)
fi
SAFE_NAME=$(printf '%s' "$PROJECT_NAME" | tr -c 'A-Za-z0-9_.-' '_')
CONTAINER_NAME="claude-docker-${SAFE_NAME}-${PROJECT_HASH}"

# Locate installed assets and state (XDG Base Directory compliant)
CLAUDE_DOCKER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-docker"
IMAGE_DIR="$CLAUDE_DOCKER_DATA/image"
STATE_DIR="$CLAUDE_DOCKER_DATA/state"

# Build the image if it doesn't exist yet
if ! docker image inspect claude-docker:latest &>/dev/null; then
    echo "Docker image 'claude-docker:latest' not found."
    read -rp "Build it now? [Y/n] " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
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
        # Detect host editor from $EDITOR / $VISUAL. Recognized binaries map
        # to: vim|vi → vim, nano → nano, emacs → emacs, emacsclient →
        # emacsclient (installs emacs-nox; EDITOR is set to "emacsclient -t
        # -a ''" so it opens a terminal frame and auto-starts the daemon on
        # first use). Anything else (or unset) falls through to the
        # Dockerfile default (nano).
        DETECTED_EDITOR=""
        for candidate in "${EDITOR:-}" "${VISUAL:-}"; do
            [[ -z "$candidate" ]] && continue
            bin="$(basename "${candidate%% *}")"
            case "$bin" in
                vim|vi)      DETECTED_EDITOR="vim";         break ;;
                nano)        DETECTED_EDITOR="nano";        break ;;
                emacs)       DETECTED_EDITOR="emacs";       break ;;
                emacsclient) DETECTED_EDITOR="emacsclient"; break ;;
            esac
        done
        if [[ -n "$DETECTED_EDITOR" && "$DETECTED_EDITOR" != "nano" ]]; then
            prompt_name="$DETECTED_EDITOR"
            if [[ "$DETECTED_EDITOR" == "emacsclient" ]]; then
                prompt_name="emacs"
                echo "Note: your EDITOR is emacsclient — installing emacs and setting"
                echo "      EDITOR to \"emacsclient -t -a ''\" so tools open a terminal"
                echo "      frame and an emacs daemon auto-starts on first use."
            fi
            read -rp "Install host editor '$prompt_name' in the image? [Y/n] " ed_answer
            if [[ ! "$ed_answer" =~ ^[Nn]$ ]]; then
                BUILD_ARGS+=(--build-arg EDITOR_CHOICE="$DETECTED_EDITOR")
                if [[ "$DETECTED_EDITOR" == "emacsclient" ]]; then
                    BUILD_ARGS+=(--build-arg EDITOR_CMD="emacsclient -t -a ''")
                fi
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

# ── Per-project Claude state ─────────────────────────────────────────────────
# Session transcripts and prompt history are persisted on the host, keyed by
# the same hash we use for the container name, so each project gets its own
# isolated history that survives container removal (--rm).
#
# We mount individual subpaths of ~/.claude/ rather than using CLAUDE_CONFIG_DIR
# to relocate the whole dir. CLAUDE_CONFIG_DIR would also move .credentials.json
# into the per-project folder — forcing a re-auth for every project and
# scattering auth tokens across project state dirs. Keeping credentials.json
# and claude.json global (mounted below) avoids that.
#
# We persist:
#   projects/       — session transcripts (JSONL), enables --resume / --continue
#   history.jsonl   — up-arrow prompt recall
#   todos/          — TaskCreate/TaskUpdate state
#
# We intentionally do NOT persist shell-snapshots/. Those capture the shell's
# functions/aliases/env so the Bash tool can replay them cheaply. Inside this
# container the shell is the container's own bash sourcing the Dockerfile-built
# .bashrc (PS1, PATH, COLORTERM) — not your host shell — so the snapshots are
# small and not worth the mount.
PROJECT_STATE="$STATE_DIR/projects/$PROJECT_HASH"
mkdir -p "$PROJECT_STATE"/sessions "$PROJECT_STATE"/todos
touch "$PROJECT_STATE/history.jsonl"
touch "$PROJECT_STATE/bash_history"

CLAUDE_FLAGS=""
if [[ "$YOLO" == 1 ]]; then
    CLAUDE_FLAGS="--dangerously-skip-permissions"
fi

case "$MODE" in
    tmux)   RUN_CMD=(tmux new-session "claude $CLAUDE_FLAGS") ;;
    bash)   RUN_CMD=(bash) ;;
    claude) RUN_CMD=(bash -c "claude -c $CLAUDE_FLAGS || claude $CLAUDE_FLAGS") ;;
    exec)   RUN_CMD=(bash -c "$CUSTOM_CMD") ;;
esac

# If the container is already running (e.g. a second `claude-docker ~/proj`
# invocation), exec into it rather than trying to `docker run --name ...`
# again — which would fail with a name collision. For tmux we try attaching
# to the existing session first; otherwise we exec RUN_CMD in the container.
if [[ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ]]; then
    if [[ "$MODE" == tmux ]] && docker exec -it "$CONTAINER_NAME" tmux attach 2>/dev/null; then
        exit 0
    fi
    exec docker exec -it "$CONTAINER_NAME" "${RUN_CMD[@]}"
fi

docker run -it --rm --name "$CONTAINER_NAME" \
    --mount type=bind,source="$PROJECT_ABS",destination="/home/codesensei/$PROJECT_NAME" \
    -v "$STATE_DIR/credentials.json":/home/codesensei/.claude/.credentials.json \
    -v "$STATE_DIR/claude.json":/home/codesensei/.claude.json \
    -v "$PROJECT_STATE/sessions":/home/codesensei/.claude/projects \
    -v "$PROJECT_STATE/history.jsonl":/home/codesensei/.claude/history.jsonl \
    -v "$PROJECT_STATE/todos":/home/codesensei/.claude/todos \
    -v "$PROJECT_STATE/bash_history":/home/codesensei/.bash_history \
    ${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"} \
    -w "/home/codesensei/$PROJECT_NAME" \
    claude-docker \
    "${RUN_CMD[@]}"
