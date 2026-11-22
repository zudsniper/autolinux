# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Core CLI tools, build essentials, btop/nvtop, runtime libs"
MOD_GROUP="core"
MOD_PROFILES="minimal full"
PKGS=(curl wget jq git vim tmux htop btop nvtop build-essential pkgconf
      python3 python-is-python3 openssh-server ca-certificates gnupg lsb-release
      software-properties-common apt-transport-https net-tools ethtool fail2ban
      xclip wl-clipboard p7zip-full unzip icoutils imagemagick ffmpeg whiptail
      libnotify4 libnss3 libsecret-1-0 xdg-utils)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
