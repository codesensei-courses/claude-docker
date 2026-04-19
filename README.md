# claude-docker

Run [Claude Code](https://claude.ai/code) inside a Debian container, against any
project on your machine, with a single short command.

Similar in spirit to Anthropic's official Claude sandbox image, but more
convenient for everyday use: your login, theme, and other Claude settings are
persisted across runs, easy customization, and more.

## Why

- **Isolation.** Claude Code runs with full access to whatever directory you
  point it at. Running it inside a container means it can't wander outside the
  bind-mount into the rest of your home directory.
- **Convenience.** `claude-docker ~/some-project` and you're in.

## Installation

Requirements: Docker, Bash, Linux or Mac OS.

```sh
git clone https://github.com/<you>/claude-docker.git
cd claude-docker
./install.sh
```

`install.sh` places two things on your system (XDG-compliant paths, overridable
via `XDG_BIN_HOME` and `XDG_DATA_HOME`):

- `~/.local/bin/claude-docker` — the launcher script.
- `~/.local/share/claude-docker/image/Dockerfile` — the build context used the
  first time you run the launcher.

Make sure `~/.local/bin` is on your `PATH` — `install.sh` will warn you if it
isn't. The Docker image itself is not built at install time; it's built on
first use, or when you delete it and re-run the launcher (see *Rebuild /
update*).

Runtime state (your Claude login and settings) lives in a third location,
created on first run:

- `~/.local/share/claude-docker/state/` — `credentials.json` and `claude.json`.

## Uninstallation

To remove everything claude-docker installed:

```sh
rm ~/.local/bin/claude-docker
rm -rf ~/.local/share/claude-docker
docker image rm claude-docker:latest
```

The first line removes the launcher, the second removes the build context
**and** your persisted Claude login/settings, and the third removes the built
image. If you only want to reset the image and keep your login, skip the
`rm -rf` and only remove `~/.local/share/claude-docker/image/`.

## Usage

Point it at any project directory:

```sh
claude-docker ~/dev/my_website
```

On first run it will offer to build the image (a few minutes). On subsequent
runs it starts instantly. 

Inside the container your project is mounted at `/home/codesensei/<project>`
and Claude Code launches automatically.

## What gets persisted

Stored on the host under `~/.local/share/claude-docker/state/` and bind-mounted
into the container:

- `credentials.json` — your Claude login, so you only authenticate once.
- `claude.json` — theme, onboarding state, and other Claude Code settings.

Everything else in the container is ephemeral.

## Rebuild / update

There is no dedicated update command. To rebuild from a fresh Dockerfile
(e.g. after pulling new changes, or to pick up newer base packages), delete the
image and re-run the launcher — it will offer to build again:

```sh
docker image rm claude-docker:latest
claude-docker ~/dev/my_website
```

Your persisted login and settings survive the rebuild.

