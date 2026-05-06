# shellcheck shell=bash
# Stage 11: thin wrapper around the existing app_install.sh.
# The existing script already gates each install with is_*_installed checks,
# so re-running is safe. Marker file lets us short-circuit on full success.

S11_MARKER="$AUTOLINUX_STATE_DIR/.app_install.done"

s11_detect() {
    [ -e "$S11_MARKER" ]
}

s11_precheck() {
    check_dpkg_sane || return 1
    return 0
}

s11_execute() {
    local script="$AUTOLINUX_REPO_DIR/app_install.sh"
    [ -x "$script" ] || { log_error "missing $script"; return 1; }

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$script"
        return 0
    fi

    # The script writes /tmp/autolinux_install_status.txt — surface it on failure.
    "$script"
    local rc=$?
    if [ -r /tmp/autolinux_install_status.txt ]; then
        cp -f /tmp/autolinux_install_status.txt "$AUTOLINUX_LOG_DIR/app_install_status.txt" 2>/dev/null || true
    fi
    if [ "$rc" -ne 0 ]; then
        log_error "app_install.sh exited $rc — see $AUTOLINUX_LOG_DIR/app_install_status.txt"
        return "$rc"
    fi
    touch "$S11_MARKER"
}

s11_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    [ -e "$S11_MARKER" ]
}
