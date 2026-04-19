# claude-docker

Run [Claude Code](https://claude.ai/code) inside a Debian container, against any project on your machine, with a single short command.

The docker container will be isolated - with access only to a specific project, but your login, theme, and other Claude settings are persisted across runs and across projects. 

After installing this, you just run `claude-docker ~/some-project` to instantly have claude running in any project.

## Features
- Persists claude login and global settings like theme
- Add some nice things (man pages, bat, ripgrep, tmux, ...)
- Automatically detects setup including timezone, locale, editor (vim/nano/emacs)
- Very easy to mount extra files and add custom packages and settings to the dockerfile
- Automatically start and attach to tmux session

## Quick Start

Clone this repo, then run
``` sh
./install.sh
```

That's it. After that you should be able to run 

``` sh
claude-docker ~/somedir_myproject
```

Or, if you are currently in a project:
``` sh
# Start claude right here
claude-docker .
```

And that's it! This will start a docker container for running claude, with only access to this project.

The first time, this will ask you some question about configuration (you can just accept the defaults) and it will build a Docker image for you.

## Mounting extra files
You might want to make a certain file available in all your editing sessions (like your gitconfig or your editor config).

The easiest way is to drop the file (or a symlink to it) into `~/.local/share/claude-docker/home/`. Anything there shows up at the matching path under `/home/codesensei/` inside the container on every run. For example, to share your tmux config:

```sh
ln -s ~/.tmux.conf ~/.local/share/claude-docker/home/.tmux.conf
```

That's it — your next `claude-docker` session will use your tmux keybindings.

> **Tip:** mounts via `home/` are read-write, which is fine for harmless configs like `.tmux.conf`. For anything where a container-side change could affect your host (`.gitconfig`, `.ssh`, credentials, ...), mount it read-only via `mounts.conf` instead. For example, to share your gitconfig read-only, add this line to `~/.local/share/claude-docker/mounts.conf`:
>
> ```
> ~/.gitconfig:/home/codesensei/.gitconfig:ro
> ```

For paths outside `$HOME` or other advanced cases, see the *Mounting extra files (dotfiles, configs, ...)* section further down.


# Installation

Requirements: Docker, Bash, Linux or Mac OS.

```sh
git clone https://github.com/rjekker/claude-docker.git
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
- `~/.local/share/claude-docker/mounts.conf` and
  `~/.local/share/claude-docker/home/` — optional hooks for mounting extra
  host files into the container on every run. See *Mounting extra files*.

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

### Options

Pick what runs inside the container with one of these mutually-exclusive flags
(default is `-c`):

- `-c` — continue the last Claude Code session for this project, or start a
  new one if none exists. Equivalent to `claude -c || claude`.
- `-t` — tmux mode. If a container for this project is already running,
  attach to its tmux session; otherwise start a new container with Claude in
  a fresh tmux session. Useful when you want to detach/reattach or have
  multiple terminal windows share one Claude session.
- `-b` — drop into a plain bash shell instead of launching Claude. Handy for
  poking around the container, inspecting mounts, or running one-off commands
  with the project's env.
- `-e <cmd>` — run a custom command inside the container via `bash -c`.
  The command string is passed to bash unchanged, so shell syntax like `&&`,
  `||`, pipes, and redirections all work. Quote the whole command to keep
  your host shell from interpreting it first.
- `-y` — yolo mode: run Claude with `--dangerously-skip-permissions` so it
  never prompts for tool approval inside this container. Combines with `-c`
  (default) and `-t`; ignored by `-b` and `-e`. The container itself is
  already sandboxed to the project dir plus your configured mounts, so
  bypassing in-app prompts is reasonably safe — but anything you expose via
  `mounts.conf` or the `home/` overlay (especially read-write) is now
  fair game for Claude, so double-check those before using `-y`.

  > **Note:** `-y` only takes effect when a **new** container is started.
  > If a container for this project is already running, the launcher just
  > `docker exec`s into it and the existing Claude process keeps whatever
  > permission mode it was launched with. Exit the running container first
  > if you want to flip yolo mode on or off.

```sh
claude-docker -t ~/dev/my_website    # tmux-backed session
claude-docker -b ~/dev/my_website    # just a shell
claude-docker ~/dev/my_website       # same as -c
claude-docker -y ~/dev/my_website    # claude with skipped permission prompts
claude-docker -e 'npm test && npm run build' ~/dev/my_website
```

### Making a flag the default

If you always want a particular mode, alias the launcher in your shell rc
(`~/.bashrc`, `~/.zshrc`, ...):

```sh
# always run inside tmux
alias claude-docker='claude-docker -t'

# always drop straight into a shell
alias claude-docker='claude-docker -b'

# always run a specific command
alias cdtest='claude-docker -e "npm test && npm run build"'

# always skip permission prompts
alias claude-docker='claude-docker -y'
```

Reload your shell (or `source ~/.bashrc`) and `claude-docker ~/dev/my_website`
will behave as if you'd typed the flag. You can still override on a one-off
basis by passing a different flag — later flags win, so
`claude-docker -c ~/dev/my_website` falls back to the default Claude session
even if your alias sets `-t`.

## What gets persisted

State lives on the host under `~/.local/share/claude-docker/state/` and is
bind-mounted into the container. Two tiers:

**Global** (shared across all projects):

- `credentials.json` — your Claude login, so you only authenticate once.
- `claude.json` — theme, onboarding state, and other Claude Code settings.

**Per-project** (under `state/projects/<hash>/`, keyed by the absolute path of
the project directory so same-named projects in different locations stay
isolated):

- `sessions/` — Claude Code session transcripts, enabling `claude -c` /
  `claude -r` to resume prior conversations for this project.
- `history.jsonl` — Claude Code prompt history (up-arrow recall inside Claude).
- `todos/` — TaskCreate/TaskUpdate state.
- `bash_history` — shell history for the container's bash. Scoped per-project
  so up-arrow doesn't dredge up commands referencing a different project's
  paths.

Everything else in the container is ephemeral (it runs with `--rm`).

### Per-project permissions and settings

When you're using Claude Code and it asks "allow this tool?", you can pick
"always allow". That choice has to be remembered somewhere — and Claude Code
remembers it in a small folder called `.claude/` that lives **inside your
project**, next to your code. Two files there matter:

- `.claude/settings.json` — project-wide settings. Check this into git if you
  want your whole team to share the same rules.
- `.claude/settings.local.json` — your personal choices for this project.
  Usually gitignored. This is where the "always allow" prompts end up.

`claude-docker` doesn't do anything special to save these, and it doesn't
need to. Your project folder is already shared with the container (that's how
Claude can edit your files in the first place), so when Claude writes to
`.claude/settings.local.json` inside the container, the change lands on your
host — right there in the project — and is still there next time you open it.

The nice side-effect: the permissions you approve for one project **don't
carry over to other projects**. Each project keeps its own `.claude/` folder
and its own list of what's allowed, which is usually what you want.

> **Secrets in bash history:** the container sets `HISTCONTROL=ignoreboth`,
> which means any command typed with a **leading space** is not saved to
> history. Handy when you occasionally need to paste a token or password on
> the command line — prefix with a space and it won't land in the persisted
> `bash_history`. Note this only affects bash's own history; the command is
> still visible to other processes (e.g. `ps`) while it runs, so prefer
> `--token-file`, stdin, or env vars when the tool supports them.

## Mounting extra files (dotfiles, configs, ...)

Two optional mechanisms let you bring host files into the container on every
run — useful for things like `.gitconfig`, `.ssh`, or an `.emacs.d`. Both live
under `~/.local/share/claude-docker/` and are read by the launcher; neither
requires rebuilding the image.

> **Note:** mount changes take effect only when a **new** container
> starts. If a `claude-docker` container is already running, this
> reuses the mounts that were set when it was first launched. Exit the
> running container (so `docker run` fires fresh on the next
> invocation) for changes to `mounts.conf` or `home/` to apply.

### 1. Home overlay directory

Anything you drop into `~/.local/share/claude-docker/home/` is bind-mounted at
the matching path under `/home/codesensei/` inside the container. Simplest
for the common case of "make my dotfiles appear in my home dir":

```sh
mkdir -p ~/.local/share/claude-docker/home
ln -s ~/.gitconfig ~/.local/share/claude-docker/home/.gitconfig
ln -s ~/.emacs.d   ~/.local/share/claude-docker/home/.emacs.d
```

Symlinks are fine — they're resolved by Docker at mount time, so edits on the
host show up inside the container immediately. Dotfiles are included.

Only entries that already exist in `home/` are mounted — new paths the
container writes (e.g. `/home/codesensei/.cache/foo`) go to the container's
ephemeral layer and disappear on exit. However, bind mounts are two-way, so
if you overlay a *directory* (e.g. `.emacs.d/`), files the container writes
inside it **will** appear on the host under
`~/.local/share/claude-docker/home/.emacs.d/`. That's usually what you want
for stateful tools (emacs caches, shell history), but if you'd rather keep
the host copy pristine, use `mounts.conf` with `:ro` instead.

### 2. `mounts.conf` — explicit mount specs

For mounts that don't fit the "home overlay" model (files outside `$HOME`,
read-only mounts, custom destination paths), create
`~/.local/share/claude-docker/mounts.conf` with one spec per line:

```
# Format: src:dst[:ro]     — # and blank lines are comments
# "~" in src expands to $HOME.

~/.gitconfig:/home/codesensei/.gitconfig:ro
~/.ssh:/home/codesensei/.ssh:ro
~/work/shared-notes:/home/codesensei/notes
```

Missing sources are warned about and skipped rather than failing the run. Use
the `:ro` suffix for anything you don't want the container to be able to
modify (credentials, shared configs).

You can combine both mechanisms; specs from `mounts.conf` and entries from
`home/` are all passed to `docker run`.

## Customizing the build

`~/.local/share/claude-docker/image/build-extras.sh` is a hook script that runs
as the `codesensei` user at the end of the Docker build. Edit it to install
extra packages, drop in dotfiles, or otherwise customize your image.
Passwordless `sudo` is available for anything that needs root.

After editing, rebuild the image:

```sh
docker image rm claude-docker:latest
claude-docker ~/dev/my_website
```

Your edits are preserved across upgrades: `install.sh` only writes the default
`build-extras.sh` if the file does not already exist.

## Rebuild / update

There is no dedicated update command. To rebuild from a fresh Dockerfile
(e.g. after pulling new changes, or to pick up newer base packages), delete the
image and re-run the launcher — it will offer to build again:

```sh
docker image rm claude-docker:latest
claude-docker ~/dev/my_website
```

Your persisted login and settings survive the rebuild.

