# shellcheck shell=bash
# Stage 02: hold critical packages so apt autoremove cannot cascade them out
# during the xfce purge.

s02_detect() {
    # All currently-installed critical packages must be held.
    local pkg held
    held="$(apt-mark showhold 2>/dev/null)"
    for pkg in "${AUTOLINUX_CRITICAL_HOLDS[@]}"; do
        if is_package_installed "$pkg"; then
            echo "$held" | grep -qx "$pkg" || return 1
        fi
    done
    return 0
}

s02_precheck() { return 0; }

s02_execute() {
    log_info "current holds:"
    apt-mark showhold 2>/dev/null | sed 's/^/    /' || true

    hold_packages "${AUTOLINUX_CRITICAL_HOLDS[@]}"

    log_info "post-stage holds:"
    apt-mark showhold 2>/dev/null | sed 's/^/    /' || true
}

s02_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s02_detect
}
