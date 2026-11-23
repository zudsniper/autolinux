# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="QEMU/KVM + libvirt + virt-manager"
MOD_GROUP="dev"
MOD_PROFILES="full"
PKGS=(qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virt-manager)
mod_detect() { all_packages_installed "${PKGS[@]}" && id -nG "$(real_user)" | grep -qw libvirt; }
mod_install() {
    apt_install "${PKGS[@]}" || return 1
    run_or_dry usermod -aG libvirt,kvm "$(real_user)"
}
