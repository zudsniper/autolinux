# shellcheck shell=bash
# Stage 04: install the GNOME stack.
# Idempotent — only runs apt-install for packages not already present.

# Packages we want present after this stage. On Ubuntu 25.10 some of the
# metapackages are split (gnome-session vs gnome-session-bin); we treat the
# *-bin/-common packages as evidence the metapackage's role is filled.
S04_PACKAGES=(
    ubuntu-desktop
    gdm3
    gnome-shell
    gnome-session
    gnome-terminal
    gnome-control-center
    gnome-tweaks
)

# Packages that satisfy a S04_PACKAGES entry even if the named meta isn't installed.
# Format: "wanted=alt1|alt2".
S04_ALIASES=(
    "gnome-session=gnome-session-bin"
)

_s04_satisfied() {
    local want="$1"
    is_package_installed "$want" && return 0
    local entry alts alt
    for entry in "${S04_ALIASES[@]}"; do
        if [ "${entry%%=*}" = "$want" ]; then
            alts="${entry#*=}"
            for alt in ${alts//|/ }; do
                is_package_installed "$alt" && return 0
            done
        fi
    done
    return 1
}

s04_detect() {
    local pkg
    for pkg in "${S04_PACKAGES[@]}"; do
        _s04_satisfied "$pkg" || return 1
    done
    return 0
}

s04_precheck() {
    check_dpkg_sane || return 1
    return 0
}

s04_execute() {
    local missing=()
    local pkg
    for pkg in "${S04_PACKAGES[@]}"; do
        _s04_satisfied "$pkg" || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        log_skip "all GNOME-stack packages already installed"
        return 0
    fi

    log_info "missing packages: ${missing[*]}"
    log_info "running apt-get update…"
    run_or_dry apt-get update -qq

    log_info "installing GNOME stack…"
    # --no-install-recommends would slim things, but ubuntu-desktop relies on
    # recommends for a usable session — keep them on.
    run_or_dry env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "${missing[@]}"
}

s04_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s04_detect
}
