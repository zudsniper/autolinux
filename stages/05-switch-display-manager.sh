# shellcheck shell=bash
# Stage 05: switch the default display manager to GDM3.
# Uses dpkg-reconfigure with debconf preseeding so it works non-interactively.

s05_detect() {
    [ "$(detect_dm)" = "gdm3" ] && [ "$(cat /etc/X11/default-display-manager 2>/dev/null)" = "/usr/sbin/gdm3" ]
}

s05_precheck() {
    is_package_installed gdm3 || { log_error "gdm3 not installed; stage 04 should have done this"; return 1; }
    return 0
}

s05_execute() {
    backup_file /etc/X11/default-display-manager

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "echo 'set shared/default-x-display-manager gdm3' | debconf-communicate"
        log_dryrun "DEBIAN_FRONTEND=noninteractive dpkg-reconfigure gdm3"
        return 0
    fi

    # Preseed debconf so dpkg-reconfigure is non-interactive.
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo "gdm3 shared/default-x-display-manager select gdm3" | debconf-set-selections
        echo "shared/default-x-display-manager select gdm3"      | debconf-set-selections
    fi

    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure gdm3 \
        || log_warning "dpkg-reconfigure gdm3 returned non-zero — verifying manually"

    # Belt-and-suspenders: write the file directly.
    echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager

    # Stop lightdm if it happens to be running (it shouldn't be in our flow,
    # but if a Xubuntu install left it active we want gdm3 next reboot).
    if is_service_active lightdm; then
        log_info "stopping lightdm (gdm3 will start at next boot)"
        systemctl disable lightdm 2>/dev/null || true
    fi
}

s05_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s05_detect
}
