# shellcheck shell=bash
# Stage 08: surgically remove XFCE/Xubuntu packages.
#
# Two hard guards:
#  1. Refuse to run inside an XFCE session (would kill the running shell).
#  2. Compute the purge set live, subtracting any package that ubuntu-desktop /
#     ubuntu-desktop-minimal / gnome-shell depend on. Never ship a static kill list.

s08_detect() {
    # Detection succeeds when the safe purge set is empty — nothing left to remove.
    local set
    set="$(compute_xfce_purge_set 2>/dev/null)"
    [ -z "$set" ]
}

s08_precheck() {
    if inside_xfce_session; then
        log_error "Refusing to purge XFCE while inside an XFCE session."
        log_error "Reboot into GNOME first (stage 06 should have arranged this)."
        return 1
    fi
    check_dpkg_sane || return 1
    # Holds must already be in place (stage 02). In --dry-run, stage 02 didn't
    # actually run apt-mark, so accept the dry-run case.
    if [ "${AUTOLINUX_DRY_RUN:-0}" != "1" ]; then
        if ! apt-mark showhold 2>/dev/null | grep -qx ubuntu-desktop; then
            log_error "ubuntu-desktop is not held — refusing to purge XFCE without that safety net."
            log_error "Run: sudo ./bootstrap.sh --only 02-hold-critical-packages"
            return 1
        fi
    fi
    return 0
}

s08_execute() {
    local purge_set
    purge_set="$(compute_xfce_purge_set)"

    if [ -z "$purge_set" ]; then
        log_skip "no XFCE/Xubuntu packages to purge"
        return 0
    fi

    log_warning "computed purge set:"
    echo "$purge_set" | sed 's/^/    /'

    log_info "the following XFCE-pattern packages are KEPT (in GNOME dep closure):"
    local kept
    kept="$(compute_xfce_keep_audit)"
    if [ -z "$kept" ]; then
        echo "    (none)"
    else
        echo "$kept" | sed 's/^/    (kept) /'
    fi

    log_confirm "Purge the listed packages?" || { log_warning "aborted"; return 1; }

    # Capture pre-purge dpkg state for the log.
    log_info "snapshot of manually installed packages before purge:"
    apt-mark showmanual | wc -l | sed 's/^/    line count: /'

    local pkgs
    # shellcheck disable=SC2206
    pkgs=( $purge_set )

    if ! run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"; then
        log_error "apt-get purge failed"
        return 1
    fi

    # Record the purge in state.
    local p
    for p in "${pkgs[@]}"; do
        state_array_append purged "$p"
    done

    log_info "running apt-get autoremove…"
    run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y

    log_info "post-purge manually-installed line count:"
    apt-mark showmanual | wc -l | sed 's/^/    line count: /'

    # Sanity: GNOME stack must still be present. We check ubuntu-desktop, gdm3,
    # gnome-shell directly. For gnome-session we accept either the metapackage
    # or its -bin variant (the meta isn't always installed on Ubuntu 25.10).
    local pkg
    for pkg in ubuntu-desktop gdm3 gnome-shell; do
        if ! is_package_installed "$pkg"; then
            log_error "POST-PURGE ALARM: $pkg is no longer installed!"
            log_error "This should not happen with the holds in place. Check apt history."
            return 1
        fi
    done
    if ! is_package_installed gnome-session && ! is_package_installed gnome-session-bin; then
        log_error "POST-PURGE ALARM: neither gnome-session nor gnome-session-bin is installed!"
        return 1
    fi
    log_success "GNOME stack intact after purge"
}

s08_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s08_detect
}
