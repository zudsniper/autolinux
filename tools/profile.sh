#!/bin/bash
# Profile the current machine so the repo can be refreshed from it.
#
#   ./tools/profile.sh                  # Markdown report on stdout
#   ./tools/profile.sh --update-dconf   # also rewrite dconf/tilingshell.ini from this machine
#
# Run as your normal user (not sudo) inside your GNOME session. Read-only
# unless --update-dconf is given. Compare the report with
# `sudo ./install.sh --dry-run` to see what the repo doesn't cover yet.

set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_DCONF=0
[ "${1:-}" = "--update-dconf" ] && UPDATE_DCONF=1

section() { printf '\n## %s\n\n' "$1"; }
code()    { echo '```'; cat; echo '```'; }

. /etc/os-release
echo "# Machine profile — $(hostname) — $(date -I)"
echo
echo "- OS: $PRETTY_NAME, kernel $(uname -r)"
echo "- Session: ${XDG_SESSION_TYPE:-?} / ${XDG_CURRENT_DESKTOP:-?}, $(gnome-shell --version 2>/dev/null || echo 'no gnome-shell')"
echo "- kitty: $(kitty --version 2>/dev/null || echo 'not installed')"

section "GNOME extensions (user-installed)"
for d in "$HOME"/.local/share/gnome-shell/extensions/*/; do
    [ -f "$d/metadata.json" ] || continue
    uuid="$(basename "$d")"
    ver="$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m.get("version","?"))' "$d/metadata.json")"
    state="$(gnome-extensions info "$uuid" 2>/dev/null | awk -F': ' '/State/ {print $2}')"
    echo "- \`$uuid\` v$ver — ${state:-?}"
done
echo
echo "enabled-extensions: $(gsettings get org.gnome.shell enabled-extensions)"

section "Flatpak apps"
flatpak list --app --columns=application,origin 2>/dev/null | code

section "Third-party apt sources"
grep -rhoE 'https?://[^ ]+' /etc/apt/sources.list.d/ 2>/dev/null \
    | grep -vE 'archive.ubuntu.com|security.ubuntu.com' | sort -u | code

section "Cargo binaries"
cargo install --list 2>/dev/null | grep -v '^ ' | code

section "User systemd units"
ls "$HOME/.config/systemd/user" 2>/dev/null | code

section "Autostart entries"
ls "$HOME/.config/autostart" 2>/dev/null | code

section "Custom keybindings"
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ | code

section "Dock favorites"
gsettings get org.gnome.shell favorite-apps | code

section "Tiling Shell settings"
dconf dump /org/gnome/shell/extensions/tilingshell/ | grep -vE '^(layouts-json|overridden-settings|last-version)' | code

if [ "$UPDATE_DCONF" = "1" ]; then
    out="$REPO_DIR/dconf/tilingshell.ini"
    {
        echo "# Tiling Shell settings captured from the reference machine (tools/profile.sh)."
        echo "# Loaded with: dconf load / < dconf/tilingshell.ini"
        echo "[org/gnome/shell/extensions/tilingshell]"
        dconf dump /org/gnome/shell/extensions/tilingshell/ \
            | grep -E '^(cycle-layouts-backward|enable-snap-assist|enable-tiling-system|inner-gaps|outer-gaps|layouts-json|selected-layouts)='
    } > "$out"
    echo
    echo "_Updated ${out#"$REPO_DIR"/}_"
fi
