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
# If the launcher detected a host LANG and the user accepted, generate and
# default to that locale. Otherwise fall back to C.UTF-8 (always available).
# Without a UTF-8 locale, TUI apps like Claude Code may misrender box-drawing
# and other Unicode glyphs.
# Usage: docker build --build-arg LOCALE=en_US.UTF-8 ...
ARG LOCALE
RUN if [ -n "$LOCALE" ] \
        && [ "$LOCALE" != "C" ] \
        && [ "$LOCALE" != "C.UTF-8" ] \
        && [ "$LOCALE" != "POSIX" ]; then \
        echo "$LOCALE UTF-8" >> /etc/locale.gen \
        && locale-gen \
        && update-locale LANG="$LOCALE"; \
    fi
ENV LANG=${LOCALE:-C.UTF-8}

# ── Timezone ─────────────────────────────────────────────────────────────────
# If the launcher detected a host timezone and the user accepted, use it.
# Otherwise fall back to UTC.
# Usage: docker build --build-arg TZ=Europe/Amsterdam ...
ARG TZ=UTC
ENV TZ=${TZ}
RUN ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

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
# 24-bit color escapes. 
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
