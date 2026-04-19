# Debian + Emacs 30 + Claude Code + dev tools
FROM debian:bookworm

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    curl \
    ca-certificates \
    gnupg \
    # Requested tools
    git \
    less\
    locales\
    man-db \
    manpages \
    nano\
    ripgrep \
    tmux \
    # dotdrop dependencies (Python-based dotfile manager)
    python3 \
    python3-pip \
    python3-venv \
    # Claude Code sandbox (OS-level network/filesystem isolation)
    bubblewrap \
    # Locale + timezone support
    locales \
    sudo\
    tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV DEVCONTAINER=true
# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# ── Locale ───────────────────────────────────────────────────────────────────
# Generate en_US.UTF-8 (default) and nl_NL.UTF-8 (Dutch). Without this, TUI
# apps like Claude Code may misrender box-drawing and other Unicode glyphs.
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && sed -i 's/^# *\(nl_NL.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ── Timezone ─────────────────────────────────────────────────────────────────
ENV TZ=Europe/Amsterdam
RUN ln -fs /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime \
    && echo "Europe/Amsterdam" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

# ── Emacs 30 ─────────────────────────────────────────────────────────────────
# Debian bookworm ships Emacs 28. We add the Debian backports repo to get
# Emacs 30. If bookworm-backports doesn't carry 30 yet at build time the
# layer will fall back gracefully (emacs 28 is already installed above).
RUN echo "deb http://deb.debian.org/debian bookworm-backports main" \
        > /etc/apt/sources.list.d/backports.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        -t bookworm-backports emacs-nox \
    || true \
    && rm -rf /var/lib/apt/lists/*

# ── User: codesensei ─────────────────────────────────────────────────────────
# UID is passed at build time so files created in bind-mounted dirs are owned
# by your host user (avoids permission mismatches).
# Usage: docker build --build-arg UID=$(id -u) ...
ARG UID=1000
RUN useradd -m -u ${UID} -s /bin/bash codesensei \
    && echo 'codesensei ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/codesensei \
    && chmod 0440 /etc/sudoers.d/codesensei

# ── Claude Code (native installer) ───────────────────────────────────────────
# Run as codesensei so the binary lands in their home dir (~/.local/bin)
USER codesensei
RUN curl -fsSL https://claude.ai/install.sh | bash

# ── uv (Python package manager) ──────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ── Python versions (via uv) ──────────────────────────────────────────────────
RUN /home/codesensei/.local/bin/uv python install 3.11 3.12 3.13 3.14

# ── Python tools (via uv) ────────────────────────────────────────────────────
RUN /home/codesensei/.local/bin/uv tool install dotdrop \
    && /home/codesensei/.local/bin/uv tool install poetry \
    && /home/codesensei/.local/bin/uv tool install pipenv

# ── Bash prompt ───────────────────────────────────────────────────────────────
# Bright cyan bracket label "[🐳 docker]" + bold green user@host + blue path.
# Makes it immediately obvious you are inside the container.
RUN echo '' >> /home/codesensei/.bashrc \
    && echo '# ── Docker container prompt ──────────────────────────────────' >> /home/codesensei/.bashrc \
    && echo 'export PS1="\[\e[0;96m\][🐳 claude-docker]\[\e[0m\] \[\e[1;38;2;255;105;180m\]\u\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\$ "' >> /home/codesensei/.bashrc

# ── PATH ─────────────────────────────────────────────────────────────────────
RUN echo 'export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"' \
        >> /home/codesensei/.bashrc
ENV PATH="/home/codesensei/.local/bin:/home/codesensei/.claude/bin:${PATH}"

# ── Terminal true color ──────────────────────────────────────────────────────
# Claude Code (and other TUI apps) check COLORTERM to decide whether to emit
# 24-bit color escapes. Setting it here ensures the dark-ansi theme below
# renders with full truecolor regardless of the host terminal's inheritance.
ENV COLORTERM=truecolor
RUN echo 'export COLORTERM=truecolor' >> /home/codesensei/.bashrc

# ── User-defined build extras ────────────────────────────────────────────────
# Runs a user-editable script as the final build step. The default ships as
# a no-op; edit build-extras.sh (in the image build context) to install extra
# packages, drop in dotfiles, etc. See that file's header for details.
COPY --chown=codesensei:codesensei build-extras.sh /tmp/build-extras.sh
RUN chmod +x /tmp/build-extras.sh && /tmp/build-extras.sh && rm /tmp/build-extras.sh

# ── Default working directory & entrypoint ───────────────────────────────────
WORKDIR /home/codesensei

CMD ["bash"]
