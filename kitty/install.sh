#!/usr/bin/env bash
# Install the autolinux kitty config: VSCode-style per-split title bars, no GNOME
# titlebar, and a gray "super + drag to move" hint drawn by window_title_bar.py.
#
# Standalone:  curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/kitty/install.sh | bash
# From repo:   ./kitty/install.sh        (uses the files next to this script)
#
# Backs up existing files to <name>.bak-<timestamp> before replacing them,
# then live-reloads any running kitty instances.
set -euo pipefail

REPO_RAW="${AUTOLINUX_RAW:-https://raw.githubusercontent.com/zudsniper/autolinux/master}"
MIN_KITTY="0.46.0"   # window_title_bar* options need a recent kitty
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"

if [ -t 1 ]; then C_B=$'\033[1;34m' C_Y=$'\033[1;33m' C_0=$'\033[0m'; else C_B="" C_Y="" C_0=""; fi
say()  { printf '%s[kitty]%s %s\n' "$C_B" "$C_0" "$*"; }
warn() { printf '%s[kitty]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }

FILES=(kitty.conf window_title_bar.py)

# Prefer the copies beside this script (repo checkout) or AUTOLINUX_KITTY_SRC;
# fall back to downloading them.
script_dir="${AUTOLINUX_KITTY_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$CONF_DIR"

for f in "${FILES[@]}"; do
  if [ -n "$script_dir" ] && [ -f "$script_dir/$f" ]; then
    cp "$script_dir/$f" "$tmpdir/$f"
  else
    say "Downloading $f from $REPO_RAW"
    curl -fsSL "$REPO_RAW/kitty/$f" -o "$tmpdir/$f"
  fi
  [ -s "$tmpdir/$f" ] || { warn "$f is empty; aborting."; exit 1; }

  dest="$CONF_DIR/$f"
  if [ -f "$dest" ] && cmp -s "$tmpdir/$f" "$dest"; then
    say "$f already up to date"
    continue
  fi
  if [ -f "$dest" ]; then
    backup="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$dest" "$backup"
    say "Backed up existing $f to $backup"
  fi
  install -m 0644 "$tmpdir/$f" "$dest"
  say "Installed $dest"
done

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
