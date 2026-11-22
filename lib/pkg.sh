# shellcheck shell=bash
# Package helpers shared by modules/*.sh. All mutating calls go through
# run_or_dry (lib/safety.sh), so --dry-run never touches the system.

if [ -n "${_AUTOLINUX_PKG_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_PKG_SH_LOADED=1

# Modules run in subshells, so "already updated" is tracked with a stamp file
# shared by the whole run (apt_add_repo clears it when sources change).
_apt_stamp() { echo "${AUTOLINUX_LOG_DIR:-/tmp}/.apt-updated"; }
apt_update_once() {
    [ -e "$(_apt_stamp)" ] && return 0
    run_or_dry apt-get update -qq && touch "$(_apt_stamp)" 2>/dev/null
    return 0
}

# apt_install pkg...  — installs only the missing packages.
apt_install() {
    local missing=() p
    for p in "$@"; do
        is_package_installed "$p" || missing+=("$p")
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    apt_update_once
    DEBIAN_FRONTEND=noninteractive run_or_dry apt-get install -y "${missing[@]}"
}

# all_packages_installed pkg...  — detect helper.
all_packages_installed() {
    local p
    for p in "$@"; do is_package_installed "$p" || return 1; done
}

# apt_add_repo <name> <key-url> <deb-line-with-KEYRING-placeholder>
# Example:
#   apt_add_repo signal https://updates.signal.org/desktop/apt/keys.asc \
#     "deb [arch=amd64 signed-by=KEYRING] https://updates.signal.org/desktop/apt xenial main"
# Skips if any source already points at the same URL (e.g. a .sources file
# added by the vendor's own package).
apt_add_repo() {
    local name="$1" key_url="$2" line="$3"
    local keyring="/usr/share/keyrings/${name}.gpg"
    local list="/etc/apt/sources.list.d/${name}.list"
    local url
    url="$(echo "$line" | grep -oE 'https?://[^ ]+' | head -1)"
    if [ -n "$url" ] && is_repository_added "$url"; then
        return 0
    fi
    line="${line//KEYRING/$keyring}"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "curl -fsSL $key_url | gpg --dearmor -o $keyring"
        log_dryrun "echo '$line' > $list"
        return 0
    fi
    curl -fsSL "$key_url" | gpg --dearmor --yes -o "$keyring" || return 1
    echo "$line" > "$list"
    rm -f "$(_apt_stamp)"
}

ensure_flathub() {
    apt_install flatpak || return 1
    if ! flatpak remotes 2>/dev/null | grep -q '^flathub'; then
        run_or_dry flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
}

# flatpak_install <app-id>...  (system-wide, from flathub)
flatpak_install() {
    ensure_flathub || return 1
    local id
    for id in "$@"; do
        is_flatpak_installed "$id" || run_or_dry flatpak install -y --noninteractive flathub "$id" || return 1
    done
}

all_flatpaks_installed() {
    local id
    for id in "$@"; do is_flatpak_installed "$id" || return 1; done
}

# deb_install_url <url>  — download a .deb to a temp file and apt-install it.
deb_install_url() {
    local url="$1" tmp
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "apt-get install -y <deb from $url>"
        return 0
    fi
    tmp="$(mktemp --suffix=.deb)"
    curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}
