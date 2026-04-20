# claude-docker

Run [Claude Code](https://claude.ai/code) inside a Debian container, against any project on your machine, with a single short command.

## Rationale
I have lots of different projects on my machine. Some large, some small, some old, some new. It happens a lot that for a bit of maintenance here and there I want a quick Claude session. But I don't like to give Claude access to my entire computer, for obvious privacy and security reasons.

Although I sometimes run Claude in a dedicated VM in the cloud, that is also not always optimal. Having files locally available is very nice - using GUI editors, having all my tools at my fingertips, it's just very convenient.

So I want a quick way to fire up Claude for any local project, but giving it access ONLY to a specific project.

The solution: docker containers. We quickly start, stop and remove a container for a project, and destroy it immediately afterwards. 
We persist Claude login, history, shell history, and more, across runs, so the next time you do it, everything is still there.

## Quick overview
After installing this, you just run `claude-docker ~/some-project` to instantly have claude running in any project. That's it.

This project creates 1 single Docker image for all your projects. You
can customize it to install extra packages you need to support your
projects.

## Features
- Persists claude login and global settings like theme
- Add some nice things (man pages, bat, ripgrep, tmux, ...)
- Automatically detects setup including timezone, locale, editor (vim/nano/emacs)
- Very easy to mount extra files and add custom packages and settings to the dockerfile
- Automatically start and attach to tmux session
- Easy SSH forwarding

## Quick Start

Requirements: Docker, Bash, Linux or Mac OS.

Clone this repo, then run
``` sh
./install.sh
```

After that you should be able to run 

``` sh
claude-docker ~/somedir_myproject
```

Or, if you are currently in a project:
``` sh
# Start claude right here
claude-docker .
```

And that's it! That's it. The first time, this will ask you some question about configuration (you can just accept the defaults) and it will build a Docker image for you.

After that, it will start a Docker container for running Claude, with only access to this project. On subsequent runs it starts instantly.

Inside the container your project is mounted at `/home/codesensei/<project>`
and Claude Code launches automatically.

## Options

Flags come in two groups. **Mode** flags pick what runs inside the
container and work whether the container is new or already exists (the
launcher `docker exec`s into a running one, or `docker start`s and execs
into a stopped one). **Creation-only** flags configure how a fresh
container is launched and so only apply on the `docker run` that creates
it — passing them against an existing (running or stopped) container
errors out, because the settings they control are baked in at creation.

### Mode (default `-c`)

- `-c` — continue the last Claude Code session for this project, or start a
  new one if none exists. Equivalent to `claude -c || claude`.
- `-t` — tmux mode. If a container for this project is already running,
  attach to its tmux session; otherwise start a new container with Claude in
  a fresh tmux session. Useful when you want to detach/reattach or have
  multiple terminal windows share one Claude session.
- `-b` — drop into a plain bash shell instead of launching Claude.
- `-e <cmd>` — run a custom command inside the container via `bash -c`.
  The command string is passed to bash unchanged, so shell syntax like `&&`,
  `||`, pipes, and redirections all work. Quote the whole command to keep
  your host shell from interpreting it first.

### Creation-only flags

- `-y` — yolo mode: run Claude with `--dangerously-skip-permissions` so it
  never prompts for tool approval inside this container. Combines with `-c`
  (default) and `-t`; ignored by `-b` and `-e`. The container itself is
  already sandboxed to the project dir plus your configured mounts, so
  bypassing in-app prompts is reasonably safe — but anything you expose via
  `mounts.conf` or the `home/` overlay (especially read-write) is now
  fair game for Claude, so double-check those before using `-y`.

- `-s` — forward the host `ssh-agent` into the container. Only the agent
  socket is shared, so tools like `git push` over SSH can sign with your
  host keys without any private-key material being copied into the image or
  container. Works on Linux (uses `$SSH_AUTH_SOCK`) and macOS (uses Docker
  Desktop's built-in agent bridge at `/run/host-services/ssh-auth.sock`).
  On Linux, make sure an agent is actually running (`ssh-add -l` on the
  host should list your keys); on macOS with Docker Desktop, nothing
  further is required.

  > **Security:** while the container is running, any process inside it can
  > ask the forwarded agent to sign challenges with your host keys. That's
  > normal agent-forwarding behavior, but worth combining deliberately with
  > `-y`. Private keys themselves never enter the container.

- `-k` — keep the container after exit. By default the launcher passes
  `--rm` to `docker run`, so the container is destroyed the moment its
  main process exits, and the next invocation builds a fresh one. With
  `-k`, the container is left intact in "stopped" state instead; the next
  `claude-docker` for the same project resurrects it via `docker start`
  and `docker exec`. That lets in-container state (packages you
  `sudo apt install`ed, files dropped in `/tmp`, etc.) survive across
  sessions. See *When does the container stop?* below for exactly when
  "exit" happens per mode.

  > **Gotchas:** a persistent container pins its original image, so
  > rebuilding `claude-docker:latest` won't affect it until you
  > `docker rm` it. Stopped containers don't appear in `docker ps` — use
  > `docker ps -a` to see them. For most workflows you don't need `-k`:
  > the important state (sessions, history, project files) is already
  > persisted on the host via bind-mounts (see *What gets persisted*
  > below), and durable tweaks to the image are better expressed in
  > `build-extras.sh` so they survive image rebuilds too.

```sh
claude-docker -t ~/dev/my_website    # tmux-backed session
claude-docker -b ~/dev/my_website    # just a shell
claude-docker ~/dev/my_website       # same as -c
claude-docker -y ~/dev/my_website    # claude with skipped permission prompts
claude-docker -s ~/dev/my_website    # forward host ssh-agent (for git push, etc.)
claude-docker -k ~/dev/my_website    # keep the container after exit
claude-docker -e 'npm test && npm run build' ~/dev/my_website
```

### When does the container stop?

A container runs as long as its main process (PID 1) is alive, and stops
the moment that process exits. What PID 1 is — and therefore when it
exits — depends on the mode you launched with:

- `-b` — PID 1 is your bash shell. It exits when you type `exit` (or
  Ctrl-D), and the container stops immediately.
- `-e <cmd>` — PID 1 is `bash -c "<cmd>"`. As soon as the command
  finishes (whether successfully, failing, or interrupted), the
  container stops.
- `-c` (default) — PID 1 is `bash -c "claude -c || claude"`, so it
  stops as soon as you exit Claude.
- `-t` — PID 1 is `tmux new-session "claude …"`. Tmux keeps running as
  long as the session has at least one window; detach/reattach (and
  second `claude-docker -t` invocations from another terminal) don't
  stop it. The session ends — and the container stops — when its last
  window closes, which by default happens when Claude inside tmux
  exits and you haven't opened additional windows.

By default the launcher passes `--rm` to `docker run`, so "container
stops" also means "container is removed" — gone for good, and the next
`claude-docker` builds a fresh one. With `-k` the container is left in
"stopped" state instead: it's not running (and won't appear in
`docker ps` — use `docker ps -a`), but it still exists on disk. The
next `claude-docker` for that project brings it back via `docker start`;
it only truly goes away when you `docker rm` it yourself.

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
will behave as if you'd typed the flag. 

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



## Mounting extra files
You might want to make a certain file available in all your editing
sessions (like your gitconfig or your editor config).

The easiest way is to drop the file (or a symlink to it) into `~/.local/share/claude-docker/home/`. Anything there shows up at the matching path under `/home/codesensei/` inside the container on every run. For example, to share your tmux config:

```sh
ln -s ~/.tmux.conf ~/.local/share/claude-docker/home/.tmux.conf
```

That's it — your next `claude-docker` session will use your tmux keybindings.

> **Note:** mount changes take effect only when a **new** container
> starts. If a `claude-docker` container is already running, this
> reuses the mounts that were set when it was first launched. Exit the
> running container (so `docker run` fires fresh on the next
> invocation) for changes to `mounts.conf` or `home/` to apply.


> **Tip:** mounts via `home/` are read-write, which is fine for harmless configs like `.tmux.conf`. For anything where a container-side change could affect your host (`.gitconfig`, `.ssh`, credentials, ...), mount it read-only via `mounts.conf` instead. For example, to share your gitconfig read-only, add this line to `~/.local/share/claude-docker/mounts.conf`:
>
> ```
> ~/.gitconfig:/home/codesensei/.gitconfig:ro
> ```

For paths outside `$HOME` or other advanced cases, see the *Mounting extra files (dotfiles, configs, ...)* section further down.


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

Everything else in the container is ephemeral: the launcher passes `--rm`
to `docker run` by default, so the container is destroyed on exit. Pass
`-k` (see *Options*) to keep it around between sessions instead.

> **Secrets in bash history:** the container sets `HISTCONTROL=ignoreboth`,
> which means any command typed with a **leading space** is not saved to
> history. Handy when you occasionally need to paste a token or password on
> the command line — prefix with a space and it won't land in the persisted
> `bash_history`. Note this only affects bash's own history; the command is
> still visible to other processes (e.g. `ps`) while it runs, so prefer
> `--token-file`, stdin, or env vars when the tool supports them.

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
