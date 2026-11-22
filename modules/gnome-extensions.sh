# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# GNOME Shell extensions, installed as *stable releases* from
# extensions.gnome.org for the running GNOME version (no git/npm builds).
#
# Newly installed extensions are added to org.gnome.shell enabled-extensions;
# on Wayland they load at next login (GNOME can't reload the shell in place).

MOD_DESC="GNOME extensions: Tiling Shell, Hide Topbar, Clipboard Indicator (+ settings)"
MOD_GROUP="desktop"
MOD_PROFILES="minimal full"

EXTENSIONS=(
    tilingshell@ferrarodomenico.com     # tiling layouts (reacts to Super+drag)
    gnome-hide-topbar@sonersg.com       # hides the top bar
    clipboard-indicator@tudmotu.com     # panel clipboard history
)
# Previously installed by autolinux, now replaced or removed.
STALE_EXTENSIONS=(hidetopbar@mathieu.bidon.ca unite@hardpixel.eu)
# Ubuntu's bundled tiler fights Tiling Shell.
CONFLICTING_EXTENSIONS=(tiling-assistant@ubuntu.com)

_ext_dir() { echo "$(real_home)/.local/share/gnome-shell/extensions/$1"; }

_shell_major() { gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1; }

_enabled_list() { as_user gsettings get org.gnome.shell enabled-extensions 2>/dev/null; }

# _edit_list <key> <python statement transforming list `l`>
_edit_list() {
    local key="$1" expr="$2" cur new
    cur="$(as_user gsettings get org.gnome.shell "$key")"
    new="$(CUR="$cur" EXPR="$expr" python3 -I -c '
import ast, os
raw = os.environ["CUR"].strip()
raw = raw[3:].strip() if raw.startswith("@as") else raw
l = ast.literal_eval(raw) if raw else []
exec(os.environ["EXPR"])
print(repr(l))')"
    [ "$new" = "$cur" ] || as_user gsettings set org.gnome.shell "$key" "$new"
}

mod_detect() {
    local uuid enabled
    enabled="$(_enabled_list)" || return 1
    for uuid in "${EXTENSIONS[@]}"; do
        [ -f "$(_ext_dir "$uuid")/metadata.json" ] || return 1
        [[ "$enabled" == *"'$uuid'"* ]] || return 1
    done
    for uuid in "${STALE_EXTENSIONS[@]}" "${CONFLICTING_EXTENSIONS[@]}"; do
        [[ "$enabled" == *"'$uuid'"* ]] && return 1
    done
    return 0
}

_ego_install() {
    local uuid="$1" shell="$2" info url tmp
    info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell}")" \
        || { log_error "$uuid: no release for GNOME $shell on extensions.gnome.org"; return 1; }
    url="$(echo "$info" | jq -r '.download_url // empty')"
    [ -n "$url" ] || { log_error "$uuid: no download_url"; return 1; }
    tmp="$(mktemp --suffix=.zip)"
    curl -fsSL "https://extensions.gnome.org${url}" -o "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp"
    as_user gnome-extensions install --force "$tmp"
    local rc=$?
    rm -f "$tmp"
    [ "$rc" -eq 0 ] && log_success "$uuid v$(echo "$info" | jq -r .version)"
    return $rc
}

mod_install() {
    user_bus_available || { log_error "needs a running GNOME session for $(real_user)"; return 1; }
    apt_install gnome-shell-extensions gnome-shell-extension-manager gnome-tweaks jq curl unzip || return 1

    local shell uuid failed=0 installed=0
    shell="$(_shell_major)"
    [ -n "$shell" ] || { log_error "cannot determine GNOME Shell version"; return 1; }

    as_user gsettings set org.gnome.shell disable-user-extensions false

    for uuid in "${EXTENSIONS[@]}"; do
        if [ -f "$(_ext_dir "$uuid")/metadata.json" ]; then
            log_skip "$uuid already installed"
        else
            if _ego_install "$uuid" "$shell"; then installed=1; else failed=1; fi
        fi
    done

    # enabled-extensions: add ours, drop stale/conflicting ones.
    local add drop
    add="$(printf "'%s'," "${EXTENSIONS[@]}")"
    drop="$(printf "'%s'," "${STALE_EXTENSIONS[@]}" "${CONFLICTING_EXTENSIONS[@]}")"
    _edit_list enabled-extensions "l = [x for x in l if x not in [$drop]] + [x for x in [$add] if x not in l]"
    _edit_list disabled-extensions "l = [x for x in l if x not in [$add]]"
    for uuid in "${CONFLICTING_EXTENSIONS[@]}"; do
        as_user gnome-extensions disable "$uuid" >/dev/null 2>&1 || true
    done

    # Settings (written straight to dconf, so no extension schema needed).
    user_dconf_load "$AUTOLINUX_REPO_DIR/dconf/tilingshell.ini" || failed=1

    if [ "$installed" = "1" ] && [ "$(detect_session_type)" = "wayland" ]; then
        log_info "log out and back in to load newly installed extensions (Wayland)"
    fi
    return $failed
}
