#!/usr/bin/env bash
# ─── Example build-extras ─────────────────────────────────────────────────────
# An example build-extras file.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locale (en_US.UTF-8 + nl_NL.UTF-8) ───────────────────────────────────────
# Without a generated locale, TUI apps like Claude Code may misrender
# box-drawing and other Unicode glyphs.
sudo sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
sudo sed -i 's/^# *\(nl_NL.UTF-8\)/\1/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_US.UTF-8
cat >> "$HOME/.bashrc" <<'BASHRC'

# ── Locale ──
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
BASHRC

# ── Timezone ─────────────────────────────────────────────────────────────────
TZ=Europe/Amsterdam
sudo ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$TZ" | sudo tee /etc/timezone >/dev/null
sudo dpkg-reconfigure -f noninteractive tzdata
echo "export TZ=$TZ" >> "$HOME/.bashrc"

# ── Emacs 30 (from Debian bookworm-backports) ────────────────────────────────
# bookworm ships Emacs 28; backports usually carries 30. Falls through on
# failure so a missing backport doesn't break the whole build.
echo "deb http://deb.debian.org/debian bookworm-backports main" \
    | sudo tee /etc/apt/sources.list.d/backports.list >/dev/null
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
        -t bookworm-backports emacs-nox \
    || true
sudo rm -rf /var/lib/apt/lists/*

# ── uv + Python versions + Python tools ──────────────────────────────────────
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.11 3.12 3.13 3.14
uv tool install dotdrop
uv tool install poetry
uv tool install pipenv
