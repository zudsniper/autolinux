#!/usr/bin/env bash
# Install the autolinux kitty config (VSCode-style per-split title bars, no GNOME titlebar).
#
# Standalone:  curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/kitty/install.sh | bash
# From repo:   ./kitty/install.sh        (uses the kitty.conf next to this script)
#
# Backs up an existing kitty.conf to kitty.conf.bak-<timestamp> before replacing it,
# then live-reloads any running kitty instances.
set -euo pipefail

REPO_RAW="${AUTOLINUX_RAW:-https://raw.githubusercontent.com/zudsniper/autolinux/master}"
MIN_KITTY="0.46.0"   # window_title_bar* options need a recent kitty
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
DEST="$CONF_DIR/kitty.conf"

say()  { printf '\033[1;34m[kitty]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[kitty]\033[0m %s\n' "$*" >&2; }

# Prefer the copy beside this script (repo checkout); fall back to downloading it.
src=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
if [ -n "$script_dir" ] && [ -f "$script_dir/kitty.conf" ]; then
  src="$script_dir/kitty.conf"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if [ -n "$src" ]; then
  cp "$src" "$tmp"
else
  say "Downloading kitty.conf from $REPO_RAW"
  curl -fsSL "$REPO_RAW/kitty/kitty.conf" -o "$tmp"
fi
[ -s "$tmp" ] || { warn "Downloaded kitty.conf is empty; aborting."; exit 1; }

mkdir -p "$CONF_DIR"
if [ -f "$DEST" ]; then
  if cmp -s "$tmp" "$DEST"; then
    say "kitty.conf already up to date ($DEST)"
  else
    backup="$DEST.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$DEST" "$backup"
    say "Backed up existing config to $backup"
    install -m 0644 "$tmp" "$DEST"
    say "Installed $DEST"
  fi
else
  install -m 0644 "$tmp" "$DEST"
  say "Installed $DEST"
fi

# Version check + live reload
kitty_bin="$(command -v kitty || true)"
[ -z "$kitty_bin" ] && [ -x "$HOME/.local/kitty.app/bin/kitty" ] && kitty_bin="$HOME/.local/kitty.app/bin/kitty"
if [ -z "$kitty_bin" ]; then
  warn "kitty not found. Install the latest with:"
  warn "  curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin"
  exit 0
fi

ver="$("$kitty_bin" --version | awk '{print $2}')"
if [ "$(printf '%s\n%s\n' "$MIN_KITTY" "$ver" | sort -V | head -1)" != "$MIN_KITTY" ]; then
  warn "kitty $ver is older than $MIN_KITTY; the per-split title bars won't work."
  warn "Distro packages are often outdated. Upgrade with the official installer:"
  warn "  curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin"
fi

# SIGUSR1 makes running kitty instances reload their config.
if pkill -USR1 -x kitty 2>/dev/null; then
  say "Reloaded running kitty instances (kitty $ver)"
else
  say "Done (kitty $ver). Open a new kitty window to see it."
fi
say "Tip: the OS titlebar is hidden, so move windows with Super+drag."
