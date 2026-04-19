#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-docker"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

mkdir -p "$DATA_DIR/image" "$DATA_DIR/home" "$BIN_DIR"
install -m 0644 "$SRC_DIR/Dockerfile" "$DATA_DIR/image/Dockerfile"
install -m 0755 "$SRC_DIR/claude-docker.sh" "$BIN_DIR/claude-docker"

# mounts.conf is user-editable — write the default only if missing, so
# repeated install.sh runs don't clobber local customizations.
MOUNTS_CONF="$DATA_DIR/mounts.conf"
if [ ! -e "$MOUNTS_CONF" ]; then
    cat > "$MOUNTS_CONF" <<'EOF'
# ─── claude-docker mounts.conf ───────────────────────────────────────────────
# Extra bind mounts to apply on every `claude-docker` run. One spec per line:
#
#     src:dst[:ro]
#
# - src: absolute path on the host. "~" expands to $HOME.
# - dst: absolute path inside the container (typically under /home/codesensei).
# - ro:  optional — mount read-only. Omit for read-write.
#
# Lines starting with # and blank lines are ignored. Missing sources produce
# a warning and are skipped rather than failing the run.
#
# For the common case of "just make this file appear in my container home
# dir", the overlay directory is often simpler — drop files or symlinks into:
#     ~/.local/share/claude-docker/home/
# and they are mounted at the matching path under /home/codesensei/.
#
# Examples (uncomment and adapt):
#
# ~/.gitconfig:/home/codesensei/.gitconfig:ro
# ~/.ssh:/home/codesensei/.ssh:ro
# ~/work/shared-notes:/home/codesensei/notes
EOF
    chmod 0644 "$MOUNTS_CONF"
fi

# build-extras.sh is user-editable — write the default only if missing, so
# repeated install.sh runs don't clobber local customizations.
EXTRAS="$DATA_DIR/image/build-extras.sh"
if [ ! -e "$EXTRAS" ]; then
    cat > "$EXTRAS" <<'EOF'
#!/usr/bin/env bash
# ─── claude-docker build-extras ──────────────────────────────────────────────
# This script runs as the `codesensei` user near the end of the Docker build,
# after Claude Code, uv, and the base tools are installed. Edit it to
# customize your image: install extra packages, drop in dotfiles, configure
# shells, pre-install project tooling, etc. `sudo` is available (passwordless)
# for anything that needs root.
#
# Location on the host:
#     ~/.local/share/claude-docker/image/build-extras.sh
#
# After editing, rebuild the image:
#     docker image rm claude-docker:latest
#     claude-docker <your-project>
#
# The default version below is a no-op. The commented examples show common
# patterns — uncomment or replace them as you like.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Example: extra apt packages
# sudo apt-get update && sudo apt-get install -y --no-install-recommends \
#         htop jq fzf \
#     && sudo rm -rf /var/lib/apt/lists/*

# Example: clone your dotfiles
# git clone https://github.com/you/dotfiles "$HOME/.dotfiles"

EOF
    chmod 0755 "$EXTRAS"
fi

echo "Installed claude-docker to $BIN_DIR/claude-docker"
echo "Image context: $DATA_DIR/image"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Warning: $BIN_DIR is not on your PATH." >&2 ;;
esac
