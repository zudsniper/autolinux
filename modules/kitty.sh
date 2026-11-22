# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# kitty from the official binary installer (distro packages are too old for
# the per-split title bars), plus the repo's config via kitty/install.sh.

MOD_DESC="kitty terminal (official build) + config with title-bar hint"
MOD_GROUP="desktop"
MOD_PROFILES="minimal full"

KITTY_MIN="0.46.0"

_kitty_bin() { echo "$(real_home)/.local/kitty.app/bin/kitty"; }

_kitty_new_enough() {
    local v
    v="$(as_user "$(_kitty_bin)" --version 2>/dev/null | awk '{print $2}')"
    [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$KITTY_MIN" "$v" | sort -V | head -1)" = "$KITTY_MIN" ]
}

_kitty_config_current() {
    local cfg; cfg="$(real_home)/.config/kitty"
    cmp -s "$AUTOLINUX_REPO_DIR/kitty/kitty.conf" "$cfg/kitty.conf" \
        && cmp -s "$AUTOLINUX_REPO_DIR/kitty/window_title_bar.py" "$cfg/window_title_bar.py"
}

mod_detect() { _kitty_new_enough && _kitty_config_current; }

mod_install() {
    if ! _kitty_new_enough; then
        as_user_sh 'curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n' || return 1
        as_user_sh '
            set -e
            mkdir -p ~/.local/bin ~/.local/share/applications ~/.config
            ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/
            cp ~/.local/kitty.app/share/applications/kitty.desktop ~/.local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
            sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" ~/.local/share/applications/kitty*.desktop
            sed -i "s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|g" ~/.local/share/applications/kitty*.desktop
            echo kitty.desktop > ~/.config/xdg-terminals.list' || return 1
        # System-wide symlinks so scripts/launchers that expect /usr/local/bin work.
        ln -sf "$(_kitty_bin)" /usr/local/bin/kitty
        ln -sf "$(real_home)/.local/kitty.app/bin/kitten" /usr/local/bin/kitten
    fi
    as_user env AUTOLINUX_KITTY_SRC="$AUTOLINUX_REPO_DIR/kitty" bash "$AUTOLINUX_REPO_DIR/kitty/install.sh"
}
