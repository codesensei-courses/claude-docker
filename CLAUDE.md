# claude-docker

A small launcher that runs Claude Code in a per-project Debian
container, so Claude only sees the project directory plus whatever
extra files the user explicitly mounts.

## Standards
- Always support Linux and Mac OS
- Document every new or changed feature in README.md. Try to make the text beginner-friendly.
- New or updated flags should always be documented as well in the Usage section in `claude-docker.sh`

### After finishing a feature or bugfix
- Create unit tests and check that they run correctly
- Check that all documentation and comments match the reality of the codebase
- Commit to git.

### Git
- You are ONLY allowed to commit to your own "claude" branch, not to main.
- You are not allowed to push

### Unit tests
Always unit test:
- "Happy flow": expected use without errors
- Error and failure scenario's
- Combinations of different flags/features

## Shape of the codebase

- `claude-docker.sh` — the launcher. Parses flags, picks the container
  name (`claude-docker-<project>-<hash>`), builds the image on first
  use, wires up bind-mounts, and dispatches between `docker run` /
  `docker start` / `docker exec` depending on container state.
- `Dockerfile` — the per-project image. Debian bookworm + Claude Code
  CLI + a `codesensei` user. Build args (`UID`, `LOCALE`, `TZ`,
  `EDITOR_CHOICE`) let the launcher match the host at build time.
- `install.sh` — first-time setup: copies the launcher into
  `~/.local/bin` and the build context into
  `~/.local/share/claude-docker/`.

