# shellcheck shell=bash
# Stage 10: thin wrapper around the existing system_config.sh.
# Ran in --yes mode if AUTOLINUX_YES=1. Network flags given to bootstrap.sh
# (--static-ip/--gateway/--dns/--wol) arrive in AUTOLINUX_SYSCONFIG_ARGS;
# without them the network is left alone.
#
# Idempotency comes from system_config.sh itself (already checks swap state,
# fstab entries, and ssh service state). Re-running is safe.

S10_MARKER="$AUTOLINUX_STATE_DIR/.system_config.done"

s10_detect() {
    [ -e "$S10_MARKER" ]
}

s10_precheck() { return 0; }

s10_execute() {
    local script="$AUTOLINUX_REPO_DIR/system_config.sh"
    [ -x "$script" ] || { log_error "missing $script"; return 1; }

    local args=()
    [ "${AUTOLINUX_YES:-0}" = "1" ] && args+=("--yes")
    # Values are validated IPs/commas, so word-splitting is safe here.
    # shellcheck disable=SC2206
    [ -n "${AUTOLINUX_SYSCONFIG_ARGS:-}" ] && args+=($AUTOLINUX_SYSCONFIG_ARGS)

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$script ${args[*]}"
        return 0
    fi

    "$script" "${args[@]}" || return $?
    touch "$S10_MARKER"
}

s10_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    [ -e "$S10_MARKER" ]
}
