# claude-docker

Run [Claude Code](https://claude.ai/code) inside a Debian container, against any
project on your machine, with a single short command.

Similar in spirit to Anthropic's official Claude sandbox image, but more
convenient for everyday use: your login, theme, and other Claude settings are
persisted across runs, easy customization, and more.

After installing this, you just run `claude-docker ~/some-project` to instantly have claude running in any project.

## Features
- Persists claude login and global settings like theme
- Complete terminal setup including TERM, timezone and locale
- Add custom packages and settings to the dockerfile
- Automatically start and attach to tmux session

## Installation

Requirements: Docker, Bash, Linux or Mac OS.

```sh
git clone https://github.com/<you>/claude-docker.git
cd claude-docker
./install.sh
```

`install.sh` places the following on your system (XDG-compliant paths, overridable
via `XDG_BIN_HOME` and `XDG_DATA_HOME`):

- `~/.local/bin/claude-docker` — the launcher script.
- `~/.local/share/claude-docker/image/Dockerfile` — the build context used the
  first time you run the launcher.
- `~/.local/share/claude-docker/image/build-extras.sh` — a user-editable hook
  script run at the end of the build. Empty by default; see *Customizing the
  build* below.

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

## Customizing the build

`~/.local/share/claude-docker/image/build-extras.sh` is a hook script that runs
as the `codesensei` user at the end of the Docker build. Edit it to install
extra packages, drop in dotfiles, or otherwise customize your image.
Passwordless `sudo` is available for anything that needs root.

The file ships as a no-op with commented examples. A fuller reference —
showcasing my current emacs/python setup — can be found in this repo as zexample-extras.sh`.

```sh
cp ~/.local/share/claude-docker/example-extras.sh \
   ~/.local/share/claude-docker/image/build-extras.sh
```

After editing, rebuild the image:

```sh
docker image rm claude-docker:latest
claude-docker ~/dev/my_website
```

Your edits are preserved across upgrades: `install.sh` only writes the default
`build-extras.sh` if the file does not already exist. `example-extras.sh` is
refreshed on every `install.sh` run.

## Rebuild / update

There is no dedicated update command. To rebuild from a fresh Dockerfile
(e.g. after pulling new changes, or to pick up newer base packages), delete the
image and re-run the launcher — it will offer to build again:

```sh
docker image rm claude-docker:latest
claude-docker ~/dev/my_website
```

Your persisted login and settings survive the rebuild.

