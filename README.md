# claude-docker

Run [Claude Code](https://claude.ai/code) inside a Debian container, against any project on your machine, with a single short command.

Claude-docker remembers your Claude login session across projects, and it retains its project history after the docker container is destroyed.

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

And that's it! The first time, this will ask you some question about
configuration (you can just accept the defaults) and it will build a
Docker image for you. After building the image, it will start a Docker
container for running Claude, with only access to this project.

You will have to log in to Claude once, on the first container you
run. On subsequent runs it starts instantly, with a logged in Claude
session, and all your project history from previous runs.

Inside the container your project is mounted at `/home/codesensei/<project>`
and Claude Code launches automatically.

You can have multiple terminals connected to the same container, e.g.
one with bash and another with Claude).



## Rationale
I have lots of different projects on my machine. Some large, some small, some old, some new. It happens a lot that for a bit of maintenance here and there I want a quick Claude session. But I don't like to give Claude access to my entire computer, for obvious privacy and security reasons.

Although I sometimes run Claude in a dedicated VM in the cloud, that is also not always optimal. Having files locally available is very nice - using GUI editors, having all my tools at my fingertips, it's just very convenient.

So I want a quick way to fire up Claude for any local project, but giving it access ONLY to a specific project.

The solution: docker containers. We quickly start, stop and remove a container for a project, and destroy it immediately afterwards. 
We persist Claude login, history, shell history, and more, across runs, so the next time you do it, everything is still there.


## Features
- Persists claude login and global settings like theme
- Add some nice things (man pages, bat, ripgrep, tmux, ...)
- Automatically detects setup including timezone, locale, editor (vim/nano/emacs)
- Very easy to mount extra files and add custom packages and settings to the dockerfile
- Easy SSH forwarding
- And more..

## Options
You can pass the following options to `claude-docker`.

Examples:
```sh
claude-docker -t ~/dev/my_website    # tmux-backed session
claude-docker -b ~/dev/my_website    # just a shell
claude-docker ~/dev/my_website       # same as -c
claude-docker -y ~/dev/my_website    # claude with skipped permission prompts
claude-docker -s ~/dev/my_website    # forward host ssh-agent (for git push, etc.)
claude-docker -k ~/dev/my_website    # keep the container after exit
claude-docker -e 'npm test && npm run build' ~/dev/my_website
```

### Mode (default `-c`)
Pass one of these flags to determine what to run in the container.
If there is no container for the project, it will be created.

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
These flags can only be passed when you are starting a new container.
So if you are already using a container for a specific project, exit
it first before you pass these settings.

- `-y` — yolo mode: run Claude with `--dangerously-skip-permissions`
  so it never prompts for tool approval inside this container.
  Combines with `-c` and `-t`; ignored by `-b` and `-e`. The container
  itself is already sandboxed to the project dir plus your configured
  mounts, so bypassing in-app prompts is reasonably safe — but
  anything you expose via `mounts.conf` or the `home/` overlay
  (especially read-write) is now fair game for Claude, so double-check
  those before using `-y`.

- `-s` — forward the host `ssh-agent` into the container. Only the
  agent socket is shared, so tools like `git push` over SSH can sign
  with your host keys without any private-key material being copied
  into the image or container. Works on Linux (uses `$SSH_AUTH_SOCK`)
  and macOS (uses Docker Desktop's built-in agent bridge at
  `/run/host-services/ssh-auth.sock`). On Linux, make sure an agent is
  actually running (`ssh-add -l` on the host should list your keys);
  on macOS with Docker Desktop, nothing further is required. **Note**:
  while the container is running, any process inside it can ask the
  forwarded agent to sign challenges with your host keys. This can be
  dangerous when combined with `-y`. Private keys themselves never
  enter the container.

- `-k` — keep the container after exit. By default the container is
  destroyed the moment its main process exits, and the next invocation
  starts a fresh one. With `-k`, the container is left intact in
  "stopped" state instead; the next `claude-docker` for the same
  project resurrects it. That lets in-container state (packages you
  `sudo apt install`ed, files dropped in `/tmp`, etc.) survive across
  sessions. **Note**: For most workflows you don't need `-k`: the
  important state (sessions, history, project files) is already
  persisted on the host via bind-mounts and durable tweaks to the
  image are better expressed in `build-extras.sh` so they survive
  image rebuilds too.

### Making a flag the default

If you always want a particular mode, alias the launcher in your shell rc
(`~/.bashrc`, `~/.zshrc`, ...):

```sh
# always run inside tmux
alias claude-docker='claude-docker -t'
```

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

### The home folder
The easiest way is to drop the file (or a symlink to it) into
`~/.local/share/claude-docker/home/`. Anything there shows up at the
matching path under `/home/codesensei/` inside the container on every
run. For example, to share your tmux config:

```sh
ln -s ~/.tmux.conf ~/.local/share/claude-docker/home/.tmux.conf
```

That's it — your next `claude-docker` session will use your tmux keybindings.

Only entries that already exist in `home/` are mounted; that means
that new files created in the container do not automatically show up
in this folder.

However, if you add a *directory* (e.g. `.emacs.d/`), any files the
container writes inside it **will** appear on the host under
`~/.local/share/claude-docker/home/.emacs.d/`. That's usually what you
want for stateful tools (emacs caches, shell history), but can be
dangerous because now the container can write to all the files in that
folder on the host.

**Note:** mount changes take effect only when a **new** container
starts. If a `claude-docker` container is already running, you have to
exit the running container for changes to `mounts.conf` or `home/` to
apply.

**Tip:** mounts via `home/` are read-write, which is fine for harmless
configs like `.tmux.conf`. For anything where a container-side change
could affect your host (`.gitconfig`, `.ssh`, credentials, ...), mount
it read-only via `mounts.conf` instead. 

### `mounts.conf`

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

Use the `:ro` suffix (read-only) for anything you don't want the
container to be able to modify (credentials, shared configs).

You can combine both mechanisms; specs from `mounts.conf` and entries from
`home/` are all passed to `docker run`.

## What gets persisted

State lives on the host under `~/.local/share/claude-docker/state/` and is
bind-mounted into the container. Two tiers:

**Global** (shared across all projects):

- `credentials.json` — your Claude login, so you only have to authenticate once.
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
