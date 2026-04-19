FROM debian:bookworm

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    bat \
    curl \
    ca-certificates \
    gnupg \
    fd \
    fzf \
    git \
    less\
    locales\
    man-db \
    manpages \
    nano \
    ripgrep \
    tmux \
    # Claude Code sandbox (OS-level network/filesystem isolation)
    bubblewrap \
    # Locale + timezone support
    locales \
    sudo\
    tzdata \
    unzip \
    && rm -rf /var/lib/apt/lists/*


# ── Editor ───────────────────────────────────────────────────────────────────
# Chosen at build time based on the host's $EDITOR / $VISUAL. Defaults to
# nano. Supported EDITOR_CHOICE values: nano, vim, emacs, emacsclient.
# EDITOR_CMD is what tools actually invoke; defaults to EDITOR_CHOICE. For
# emacsclient the launcher passes "emacsclient -t -a ''" so tools open a
# terminal frame and emacsclient auto-starts a daemon on first use if none
# is running.
# Usage: docker build --build-arg EDITOR_CHOICE=vim ...
ARG EDITOR_CHOICE=nano
ARG EDITOR_CMD=$EDITOR_CHOICE
RUN case "$EDITOR_CHOICE" in \
        vim)               PKG=vim ;; \
        nano)              PKG=nano ;; \
        emacs|emacsclient) PKG=emacs-nox ;; \
        *)                 echo "Unknown EDITOR_CHOICE: $EDITOR_CHOICE" >&2; exit 1 ;; \
    esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends "$PKG" \
    && rm -rf /var/lib/apt/lists/*
ENV EDITOR="${EDITOR_CMD}"
ENV VISUAL="${EDITOR_CMD}"

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

# --- fzf, bat
RUN echo 'eval "$(fzf --bash)"' >> /home/codesensei/.bashrc
RUN echo 'alias cat="bat"'
RUN echo 'export MANPAGER="bat -plman"' >> /home/codesensei/.bashrc

# ── MOTD: claude session cheatsheet ──────────────────────────────────────────
# Shown on every new interactive bash shell (e.g. when a tmux window is opened
# inside the container). Colors match the PS1 prompt: cyan rules, hot-pink
# commands. Guarded on $- so non-interactive bash stays silent.
RUN cat >> /home/codesensei/.bashrc <<'EOF'

# ── Claude session MOTD ──────────────────────────────────────────────────────
if [[ $- == *i* ]]; then
    __cd_C='\e[0;96m'; __cd_P='\e[1;38;2;255;105;180m'; __cd_D='\e[2m'; __cd_R='\e[0m'
    printf "\n${__cd_C}────────────────────────────────────────────────${__cd_R}\n"
    printf "${__cd_C} 🐳 claude-docker — session commands${__cd_R}\n"
    printf "${__cd_C}────────────────────────────────────────────────${__cd_R}\n"
    printf "  ${__cd_P}%-18s${__cd_R} %s\n" 'claude'            'start a new session'
    printf "  ${__cd_P}%-18s${__cd_R} %s\n" 'claude -c'         'continue last session (cwd)'
    printf "  ${__cd_P}%-18s${__cd_R} %s\n" 'claude -r'         'pick a session to resume'
    printf "  ${__cd_P}%-18s${__cd_R} %s\n" 'claude -r <query>' 'resume by search term'
    printf "  ${__cd_P}%-18s${__cd_R} %s\n" 'claude -r <uuid>'  'resume a specific session ID'
    printf "${__cd_C}────────────────────────────────────────────────${__cd_R}\n"
    printf "${__cd_D} Sessions & prompt history persist on the host,${__cd_R}\n"
    printf "${__cd_D} keyed per project.${__cd_R}\n"
    printf "${__cd_C}────────────────────────────────────────────────${__cd_R}\n\n"
    unset __cd_C __cd_P __cd_D __cd_R
fi
EOF

# ── User-defined build extras ────────────────────────────────────────────────
# Runs a user-editable script as the final build step. The default ships as
# a no-op; edit build-extras.sh (in the image build context) to install extra
# packages, drop in dotfiles, etc. See that file's header for details.
COPY --chown=codesensei:codesensei build-extras.sh /tmp/build-extras.sh
RUN chmod +x /tmp/build-extras.sh && /tmp/build-extras.sh && rm /tmp/build-extras.sh

# ── Default working directory & entrypoint ───────────────────────────────────
WORKDIR /home/codesensei

CMD ["bash"]
