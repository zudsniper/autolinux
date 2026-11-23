#!/bin/bash
# autolinux one-line installer. Downloads the repo (no git needed) and runs
# install.sh with whatever flags you pass after `bash -s --`:
#
#   curl -fsSL https://raw.githubusercontent.com/zudsniper/autolinux/master/get.sh | bash -s -- --yes
#
# Environment:
#   AUTOLINUX_REF   branch or tag to download (default: master)
#   AUTOLINUX_DIR   where to unpack it (default: ~/.local/share/autolinux)

set -euo pipefail

REPO="zudsniper/autolinux"
REF="${AUTOLINUX_REF:-master}"
DIR="${AUTOLINUX_DIR:-$HOME/.local/share/autolinux}"

say() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die() { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required: sudo apt install -y curl"
command -v tar  >/dev/null || die "tar is required: sudo apt install -y tar"
command -v sudo >/dev/null || [ "$(id -u)" = 0 ] || die "sudo is required"

say "downloading $REPO@$REF → $DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/$REPO/archive/$REF.tar.gz" | tar -xz -C "$tmp" --strip-components=1 \
    || die "download failed (is '$REF' a valid branch or tag?)"
rm -rf "$DIR"
mkdir -p "$(dirname "$DIR")"
mv "$tmp" "$DIR"
trap - EXIT

# Give install.sh the real terminal (stdin is this script's pipe), so the
# checklist and prompts work. Without a terminal it runs non-interactively.
run=(bash "$DIR/install.sh" "$@")
[ "$(id -u)" = 0 ] || run=(sudo "${run[@]}")
if [ -r /dev/tty ] && : </dev/tty 2>/dev/null; then
    exec "${run[@]}" </dev/tty
else
    exec "${run[@]}"
fi
