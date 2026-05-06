# shellcheck shell=bash
# Stage 14: release the holds we added in stage 02.
# Reads holds_added from state.json — only releases what WE held, never anything
# the user (or another tool) had pre-held.

s14_detect() {
    # Released = none of the packages we recorded as holds_added are still held.
    local pkg held
    held="$(apt-mark showhold 2>/dev/null)"
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        echo "$held" | grep -qx "$pkg" && return 1
    done < <(jq -r '.holds_added[]?' < "$AUTOLINUX_STATE_FILE" 2>/dev/null)
    return 0
}

s14_precheck() { return 0; }

s14_execute() {
    local pkgs=()
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        pkgs+=("$pkg")
    done < <(jq -r '.holds_added[]?' < "$AUTOLINUX_STATE_FILE" 2>/dev/null)

    if [ "${#pkgs[@]}" -eq 0 ]; then
        log_skip "no holds recorded in state — nothing to release"
        return 0
    fi

    log_info "releasing holds: ${pkgs[*]}"
    unhold_packages "${pkgs[@]}"
}

s14_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s14_detect
}
