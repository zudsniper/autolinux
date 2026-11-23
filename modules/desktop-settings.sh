# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# GNOME look & behavior from dconf/desktop.ini, plus dock favorites.

MOD_DESC="GNOME settings: dark mode, accent, icons, dock size/favorites, mouse"
MOD_GROUP="desktop"
MOD_PROFILES="minimal full"

DESKTOP_INI="$AUTOLINUX_REPO_DIR/dconf/desktop.ini"
FAVORITES="['firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'com.rustdesk.RustDesk.desktop', 'kitty.desktop', 'com.discordapp.Discord.desktop', 'claude-desktop-unofficial.desktop', 'com.spotify.Client.desktop', 'google-chrome.desktop']"

# True when every key in the ini already has the given value.
_ini_applied() {
    local ini="$1"
    user_bus_available || return 1
    as_user env INI="$ini" python3 -I -c '
import os, subprocess, sys, configparser
cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.optionxform = str
cp.read(os.environ["INI"])
for sec in cp.sections():
    for k, v in cp.items(sec):
        cur = subprocess.run(["dconf", "read", f"/{sec}/{k}"], capture_output=True, text=True).stdout.strip()
        if cur != v.strip():
            sys.exit(1)'
}

mod_detect() {
    _ini_applied "$DESKTOP_INI" || return 1
    [ "$(as_user gsettings get org.gnome.shell favorite-apps)" = "$FAVORITES" ]
}

mod_install() {
    apt_install_lean python3 dconf-cli || return 1
    user_dconf_load "$DESKTOP_INI" || return 1
    as_user gsettings set org.gnome.shell favorite-apps "$FAVORITES"
}
