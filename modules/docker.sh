# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Docker Engine + compose/buildx (user added to docker group)"
MOD_GROUP="dev"
MOD_PROFILES="full"
PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
mod_detect() { all_packages_installed "${PKGS[@]}" && id -nG "$(real_user)" | grep -qw docker; }
mod_install() {
    local codename
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    apt_add_repo docker-archive-keyring https://download.docker.com/linux/ubuntu/gpg \
        "deb [arch=$(dpkg --print-architecture) signed-by=KEYRING] https://download.docker.com/linux/ubuntu $codename stable" || return 1
    apt_install "${PKGS[@]}" || return 1
    run_or_dry usermod -aG docker "$(real_user)"
    log_info "log out and back in for docker group membership to apply"
}
