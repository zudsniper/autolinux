# shellcheck shell=bash
# Run things as the desktop user from a root (sudo) context.
#
# Installers run as root, but cargo, rustup, gsettings/dconf, systemd --user and
# gnome-extensions must run as the real user *inside their session* (so they
# reach the session D-Bus). Everything here is a no-op wrapper when the
# caller already is that user.

if [ -n "${_AUTOLINUX_USER_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_USER_SH_LOADED=1

# as_user <cmd> [args...]  — run as the real user with session env + user PATHs.
as_user() {
    local u h uid
    u="$(real_user)"
    h="$(real_home "$u")"
    uid="$(id -u "$u")"
    local path="$h/.cargo/bin:$h/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [ "$(id -u)" = "$uid" ]; then
        PATH="$path" "$@"
        return
    fi
    # env -C: start in the user's home, not root's cwd (which they may not be able to read).
    sudo -u "$u" -H env -C "$h" \
        HOME="$h" USER="$u" LOGNAME="$u" PATH="$path" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        XDG_SESSION_TYPE="$(detect_session_type)" \
        XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-ubuntu:GNOME}" \
        "$@"
}

# as_user_sh '<shell snippet>'  — same, for pipelines/redirections.
as_user_sh() {
    as_user bash -o pipefail -c "$1"
}

# True when the user's session bus is reachable (gsettings/systemctl --user work).
user_bus_available() {
    local uid
    uid="$(id -u "$(real_user)")"
    [ -S "/run/user/$uid/bus" ]
}

# user_dconf_load <file.ini>  — load a dconf keyfile rooted at "/".
user_dconf_load() {
    local f="$1"
    [ -r "$f" ] || { log_error "dconf snippet not found: $f"; return 1; }
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "dconf load / < $f"
        return 0
    fi
    user_bus_available || { log_warning "no session bus for $(real_user); skipping dconf load of $f"; return 1; }
    apt_install_lean dconf-cli || return 1
    as_user dconf load / < "$f"
}

# gnome_add_keybinding <name> <command> <binding>
# Idempotent: updates an existing custom keybinding with the same name or
# command, otherwise allocates the next free customN slot.
gnome_add_keybinding() {
    apt_install_lean dconf-cli python3 || return 1
    local name="$1" cmd="$2" binding="$3"
    local base=/org/gnome/settings-daemon/plugins/media-keys
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "keybinding '$name': $binding -> $cmd"
        return 0
    fi
    user_bus_available || { log_warning "no session bus; cannot set keybinding '$name'"; return 1; }

    local list slot
    list="$(as_user dconf read "$base/custom-keybindings")"
    slot="$(
        as_user env LIST="$list" NAME="$name" CMD="$cmd" BASE="$base" python3 -I -c "$(cat <<'PY'

import ast, os, subprocess
base, name, cmd = os.environ["BASE"], os.environ["NAME"], os.environ["CMD"]
raw = os.environ.get("LIST", "").strip()
raw = raw[3:].strip() if raw.startswith("@as") else raw
paths = ast.literal_eval(raw) if raw else []
def rd(p, k):
    return subprocess.run(["dconf", "read", p + k], capture_output=True, text=True).stdout.strip().strip(chr(39))
for p in paths:
    if rd(p, "name") == name or rd(p, "command") == cmd:
        print(p); break
else:
    n = 0
    while f"{base}/custom-keybindings/custom{n}/" in paths:
        n += 1
    print(f"{base}/custom-keybindings/custom{n}/")
PY
)"
    )"
    [ -n "$slot" ] || { log_error "could not allocate keybinding slot for '$name'"; return 1; }

    as_user dconf write "${slot}name" "'$name'"
    as_user dconf write "${slot}command" "'$cmd'"
    as_user dconf write "${slot}binding" "'$binding'"

    # Append slot to the list if missing.
    as_user env LIST="$list" SLOT="$slot" python3 -I -c "$(cat <<'PY'

import ast, os, subprocess
raw = os.environ.get("LIST", "").strip()
raw = raw[3:].strip() if raw.startswith("@as") else raw
paths = ast.literal_eval(raw) if raw else []
slot = os.environ["SLOT"]
if slot not in paths:
    paths.append(slot)
    subprocess.run(["dconf", "write",
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings", repr(paths)], check=True)
PY
)"
    log_success "keybinding '$name' ($binding)"
}

# gnome_has_keybinding <command-substring>
gnome_has_keybinding() {
    user_bus_available || return 1
    as_user dconf dump /org/gnome/settings-daemon/plugins/media-keys/ 2>/dev/null | grep -qF "command='$1"
}
