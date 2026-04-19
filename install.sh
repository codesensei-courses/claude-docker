#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-docker"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

mkdir -p "$DATA_DIR/image" "$BIN_DIR"
install -m 0644 "$SRC_DIR/Dockerfile" "$DATA_DIR/image/Dockerfile"
install -m 0755 "$SRC_DIR/claude-docker.sh" "$BIN_DIR/claude-docker"

# build-extras.sh is user-editable — install the default only if missing,
# so repeated install.sh runs don't clobber local customizations.
if [ ! -e "$DATA_DIR/image/build-extras.sh" ]; then
    install -m 0755 "$SRC_DIR/build-extras.sh" "$DATA_DIR/image/build-extras.sh"
fi

echo "Installed claude-docker to $BIN_DIR/claude-docker"
echo "Image context: $DATA_DIR/image"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Warning: $BIN_DIR is not on your PATH." >&2 ;;
esac
