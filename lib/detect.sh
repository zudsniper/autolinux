# shellcheck shell=bash
# Detection helpers. All functions are read-only and safe to call repeatedly.

if [ -n "${_AUTOLINUX_DETECT_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_DETECT_SH_LOADED=1

# Real-user detection (handles sudo). Pattern from app_install.sh:680-688.
real_user() {
    local u
    u="$(logname 2>/dev/null || true)"
    [ -z "$u" ] && u="${SUDO_USER:-}"
    [ -z "$u" ] && u="$USER"
    if [ -z "$u" ] || [ "$u" = "root" ]; then
        # Fall back to the first non-system user with a real shell.
        u="$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(false|nologin)/ {print $1; exit}' /etc/passwd 2>/dev/null)"
    fi
    echo "$u"
}

real_home() {
    local u="${1:-$(real_user)}"
    getent passwd "$u" 2>/dev/null | cut -d: -f6
}

# Idempotency primitives — promoted from app_install.sh:32-51.
is_package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}
is_flatpak_installed() {
    command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | awk '{print $2}' | grep -qx "$1"
}
is_repository_added() {
    grep -rqs "$1" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
}
is_service_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}
is_service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Desktop / display-manager / session detection.
detect_de() {
    # Prefer running session signals over installed packages.
    if pgrep -x xfce4-session >/dev/null 2>&1; then echo "xfce"; return; fi
    if pgrep -x gnome-shell  >/dev/null 2>&1; then echo "gnome"; return; fi
    if pgrep -x plasmashell  >/dev/null 2>&1; then echo "kde"; return; fi
    if pgrep -x cinnamon     >/dev/null 2>&1; then echo "cinnamon"; return; fi
    if pgrep -x mate-session >/dev/null 2>&1; then echo "mate"; return; fi

    case "${XDG_CURRENT_DESKTOP:-}" in
        *XFCE*)   echo "xfce";   return ;;
        *GNOME*)  echo "gnome";  return ;;
        *KDE*)    echo "kde";    return ;;
        *MATE*)   echo "mate";   return ;;
    esac

    # Fall back to "what is installed and could plausibly be the active DE"
    if is_package_installed gnome-shell;   then echo "gnome"; return; fi
    if is_package_installed xfce4-session; then echo "xfce";  return; fi
    echo "unknown"
}

detect_dm() {
    local dmfile=/etc/X11/default-display-manager
    if [ -r "$dmfile" ]; then
        local path
        path="$(cat "$dmfile" 2>/dev/null)"
        case "$path" in
            *gdm3|*gdm)   echo "gdm3";    return ;;
            *lightdm)     echo "lightdm"; return ;;
            *sddm)        echo "sddm";    return ;;
            *)            ;;
        esac
    fi
    if is_service_active gdm.service       || is_service_active gdm3.service;       then echo "gdm3";    return; fi
    if is_service_active lightdm.service;                                            then echo "lightdm"; return; fi
    if is_service_active sddm.service;                                               then echo "sddm";    return; fi
    if is_package_installed gdm3;     then echo "gdm3";    return; fi
    if is_package_installed lightdm;  then echo "lightdm"; return; fi
    if is_package_installed sddm;     then echo "sddm";    return; fi
    echo "none"
}

detect_session_type() {
    case "${XDG_SESSION_TYPE:-}" in
        wayland|x11|tty) echo "$XDG_SESSION_TYPE"; return ;;
    esac
    # Sometimes (e.g. inside sudo) XDG_SESSION_TYPE is unset; ask loginctl.
    local user sid
    user="$(real_user)"
    sid="$(loginctl 2>/dev/null | awk -v u="$user" '$3==u {print $1; exit}')"
    if [ -n "$sid" ]; then
        loginctl show-session "$sid" 2>/dev/null | awk -F= '/^Type=/{print $2; exit}'
        return
    fi
    echo "unknown"
}

# OS gates.
require_ubuntu() {
    local id
    id="$(. /etc/os-release 2>/dev/null && echo "$ID")"
    [ "$id" = "ubuntu" ] || return 1
}
ubuntu_version_id() {
    . /etc/os-release 2>/dev/null && echo "$VERSION_ID"
}

# Capability checks for stage 06.
boot_has_two_kernels() {
    local n
    n="$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | wc -l)"
    [ "$n" -ge 2 ]
}
boot_efi_free_mb() {
    df -BM /boot/efi 2>/dev/null | awk 'NR==2 {print $4+0}'
}
disk_root_free_gb() {
    df -BG / 2>/dev/null | awk 'NR==2 {print $4+0}'
}
mem_total_gb() {
    awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo
}

is_root() { [ "$(id -u)" -eq 0 ]; }
require_root() { is_root || log_die "Must run as root (use sudo)."; }
