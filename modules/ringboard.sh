# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Ringboard clipboard manager (https://github.com/SUPERCILEX/clipboard-history).
#
# Mirrors upstream's install-with-cargo-systemd.sh, but pinned, run as the real
# user from a root context, and without piping a remote script into bash.
#
# Watcher choice: GNOME/mutter does not implement ext_data_control_v1, so on
# GNOME the X11 watcher is used even in a Wayland session (it works through
# XWayland). Other Wayland compositors are probed with wayland-interface-check,
# same as upstream. The egui window backend follows the session type.

MOD_DESC="Ringboard clipboard manager (server + watcher + egui, Ctrl+Super+Alt+V)"
MOD_GROUP="desktop"
MOD_PROFILES="minimal full"
MOD_DEPENDS="rust"

RINGBOARD_VERSION="${RINGBOARD_VERSION:-0.15.0}"
RINGBOARD_RAW="https://raw.githubusercontent.com/SUPERCILEX/clipboard-history/${RINGBOARD_VERSION}"
RINGBOARD_SHORTCUT="${RINGBOARD_SHORTCUT:-<Ctrl><Super><Alt>v}"

_rb_session() {
    local s; s="$(detect_session_type)"
    [ "$s" = "wayland" ] && echo wayland || echo x11
}

_rb_watcher() {
    if [ "$(_rb_session)" = "x11" ] || [ "$(detect_de)" = "gnome" ]; then
        echo x11; return
    fi
    if [ "${XDG_CURRENT_DESKTOP:-}" = "COSMIC" ]; then echo wayland; return; fi
    if as_user cargo install --locked wayland-interface-check >/dev/null 2>&1 \
        && as_user wayland-interface-check ext_data_control_manager_v1 >/dev/null 2>&1; then
        echo wayland
    else
        echo x11
    fi
}

_rb_unit_dir() { echo "$(real_home)/.config/systemd/user"; }

mod_detect() {
    local bin; bin="$(real_home)/.cargo/bin"
    [ -x "$bin/ringboard-server" ] && [ -x "$bin/ringboard-egui" ] || return 1
    [ -x "$bin/ringboard-x11" ] || [ -x "$bin/ringboard-wayland" ] || return 1
    [ -f "$(_rb_unit_dir)/ringboard-server.service" ] || return 1
    grep -q "clipboard-history-server $RINGBOARD_VERSION " "$(real_home)/.cargo/.crates.toml" 2>/dev/null || return 1
    gnome_has_keybinding "$bin/ringboard-egui toggle"
}

_rb_fetch_unit() {
    # _rb_fetch_unit <repo-path> <binary-name-or-empty>
    local path="$1" bin="$2" dest
    dest="$(_rb_unit_dir)/$(basename "$path")"
    as_user curl -fsSL "$RINGBOARD_RAW/$path" -o "$dest" || return 1
    if [ -n "$bin" ]; then
        as_user sed -i "s|ExecStart=$bin|ExecStart=$(real_home)/.cargo/bin/$bin|" "$dest"
    fi
}

_rb_enable_unit_offline() {
    # Fallback when there is no session bus (e.g. run from a TTY): create the
    # WantedBy symlink by hand so the watcher starts at next graphical login.
    local unit="$1" wants
    wants="$(_rb_unit_dir)/graphical-session.target.wants"
    as_user mkdir -p "$wants"
    as_user ln -sf "../$unit" "$wants/$unit"
}

mod_install() {
    local home bin watcher session v
    home="$(real_home)"; bin="$home/.cargo/bin"; v="$RINGBOARD_VERSION"

    apt_install build-essential pkgconf libfontconfig1-dev libxkbcommon-dev \
        libwayland-dev libx11-dev libxcursor-dev libxrandr-dev libxi-dev || return 1

    session="$(_rb_session)"
    watcher="$(_rb_watcher)"
    log_info "ringboard $v: watcher=$watcher, gui backend=$session, desktop=$(detect_de)"

    as_user cargo install --locked --version "$v" clipboard-history-server --no-default-features --features systemd || return 1
    as_user cargo install --locked --version "$v" clipboard-history || return 1
    as_user cargo install --locked --version "$v" clipboard-history-egui --no-default-features --features "$session,avif" \
        || as_user cargo install --locked --version "$v" clipboard-history-egui --no-default-features --features "$session" || return 1
    as_user cargo install --locked --version "$v" "clipboard-history-$watcher" --no-default-features || return 1

    as_user mkdir -p "$(_rb_unit_dir)" || return 1
    _rb_fetch_unit ringboard.slice "" || return 1
    _rb_fetch_unit server/ringboard-server.service ringboard-server || return 1
    _rb_fetch_unit "$watcher/ringboard-$watcher.service" "ringboard-$watcher" || return 1

    # Launcher + icon (upstream desktop file, patched to the toggle command).
    as_user mkdir -p "$home/.local/share/applications" "$home/.local/share/icons/hicolor/1024x1024"
    as_user curl -fsSL "$RINGBOARD_RAW/egui/ringboard-egui.desktop" -o "$home/.local/share/applications/ringboard-egui.desktop" || return 1
    as_user curl -fsSL "$RINGBOARD_RAW/logo.jpeg" -o "$home/.local/share/icons/hicolor/1024x1024/ringboard.jpeg" || true
    as_user sed -i \
        -e "s|Exec=ringboard-egui|Exec=$bin/ringboard-egui toggle|" \
        -e "s|Icon=ringboard|Icon=$home/.local/share/icons/hicolor/1024x1024/ringboard.jpeg|" \
        "$home/.local/share/applications/ringboard-egui.desktop"

    # Old autolinux versions wrote a broken system-wide launcher; remove it.
    if [ -f /usr/share/applications/ringboard-egui.desktop ]; then
        rm -f /usr/share/applications/ringboard-egui.desktop
    fi

    if user_bus_available; then
        local other=wayland; [ "$watcher" = "wayland" ] && other=x11
        as_user systemctl --user disable --now "ringboard-$other" >/dev/null 2>&1 || true
        as_user systemctl --user daemon-reload
        as_user systemctl --user restart ringboard-server || return 1
        as_user systemctl --user enable --now "ringboard-$watcher" || return 1
    else
        log_warning "no session bus: watcher will start at next graphical login"
        _rb_enable_unit_offline "ringboard-$watcher.service"
    fi

    gnome_add_keybinding "Ringboard Clipboard Toggle" "$bin/ringboard-egui toggle" "$RINGBOARD_SHORTCUT"
}
