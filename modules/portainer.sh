# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Portainer CE container (ports 8000/9443)"
MOD_GROUP="dev"
MOD_PROFILES=""
MOD_DEPENDS="docker"
mod_detect() { docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; }
mod_install() {
    run_or_dry docker volume create portainer_data || return 1
    run_or_dry docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
}
