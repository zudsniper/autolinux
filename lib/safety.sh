# shellcheck shell=bash
# Safety primitives: pre-flight checks, dpkg/apt sanity, holds, file backups.

if [ -n "${_AUTOLINUX_SAFETY_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_SAFETY_SH_LOADED=1

# Critical packages we hold across the migration so apt autoremove cannot cascade
# them out. Stage 02 holds, stage 14 unholds (using the captured list).
AUTOLINUX_CRITICAL_HOLDS=(
    ubuntu-desktop
    ubuntu-desktop-minimal
    ubuntu-minimal
    ubuntu-standard
    gdm3
    gnome-shell
    gnome-session
    linux-generic
    grub-efi-amd64
    grub-efi-amd64-signed
    shim-signed
)

# Run a command, or print it if dry-run is active. Always logs the command.
run_or_dry() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$*"
        return 0
    fi
    log_info "$ $*"
    "$@"
}

# Packaged-state sanity. Refuses to proceed if dpkg or apt is unhappy.
check_dpkg_sane() {
    if ! dpkg --audit 2>&1 | grep -q '.'; then
        : # empty output = clean
    else
        local out
        out="$(dpkg --audit 2>&1)"
        if [ -n "$out" ]; then
            log_error "dpkg --audit reports problems:"
            echo "$out" | sed 's/^/    /'
            return 1
        fi
    fi
    if ! apt-get check >/dev/null 2>&1; then
        log_error "apt-get check failed:"
        apt-get check 2>&1 | sed 's/^/    /' >&2
        return 1
    fi
    return 0
}

# How many upgradable packages are pending? Used by stage 00.
pending_upgrade_count() {
    apt list --upgradable 2>/dev/null | tail -n +2 | grep -c . || true
}

# Hold a list of packages. Captures the previously-held set into state so we know
# what NOT to release in stage 14.
hold_packages() {
    local pkg
    local before
    before="$(apt-mark showhold 2>/dev/null | sort -u)"
    for pkg in "$@"; do
        if is_package_installed "$pkg"; then
            if echo "$before" | grep -qx "$pkg"; then
                log_skip "already held: $pkg"
            else
                # Don't redirect run_or_dry's output — that would swallow the
                # dry-run preview. apt-mark is silent on success anyway.
                run_or_dry apt-mark hold "$pkg"
                state_array_append holds_added "$pkg"
            fi
        else
            log_skip "not installed (skip hold): $pkg"
        fi
    done
}

unhold_packages() {
    local pkg
    for pkg in "$@"; do
        if apt-mark showhold 2>/dev/null | grep -qx "$pkg"; then
            run_or_dry apt-mark unhold "$pkg"
        else
            log_skip "not held: $pkg"
        fi
    done
}

# Backup an arbitrary file with a timestamp suffix. Records into state for audit.
backup_file() {
    local src="$1"
    [ -e "$src" ] || { log_skip "backup: $src does not exist"; return 0; }
    local ts dest
    ts="$(date +%Y%m%d-%H%M%S)"
    dest="${src}.autolinux-backup.${ts}"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "cp -a $src $dest"
    else
        cp -a "$src" "$dest"
        state_array_append config_backups "$dest"
        log_info "backup: $src -> $dest"
    fi
}

# Bootloader integrity checks. Used before any reboot stage.
check_bootloader() {
    local ok=0

    if ! boot_has_two_kernels; then
        log_error "Less than 2 kernels in /boot — refusing to reboot."
        ok=1
    fi
    if [ -d /sys/firmware/efi ]; then
        local free
        free="$(boot_efi_free_mb)"
        if [ -z "$free" ] || [ "$free" -lt 200 ]; then
            log_error "/boot/efi has <200MB free — refusing to reboot."
            ok=1
        fi
        if command -v efibootmgr >/dev/null 2>&1; then
            if ! efibootmgr 2>/dev/null | grep -qi 'ubuntu\|Boot'; then
                log_error "efibootmgr reports no usable boot entries."
                ok=1
            fi
        fi
    else
        log_warning "Legacy BIOS boot — skipping EFI checks."
    fi

    return "$ok"
}

# Pattern that matches "things that look like XFCE/Xubuntu/LightDM cruft".
# Centralized here so the purge logic and the audit display agree.
AUTOLINUX_XFCE_PATTERN='^(xfce4|xubuntu-|libxfce4|lightdm|elementary-xfce-icon-theme|xfdesktop|xfwm4|xfconf|thunar|mousepad|orage|parole|ristretto|catfish|menulibre|mugshot|onboard|plymouth-theme-xubuntu|greybird-gtk-theme)'

# Walk dependencies of GNOME anchors and emit a sorted-unique list of packages
# that are mentioned (including alternatives). Output is conservatively over-broad
# — we use it as the "do-not-purge" set.
_compute_gnome_dep_closure() {
    {
        for anchor in ubuntu-desktop ubuntu-desktop-minimal gnome-shell gnome-session ubuntu-minimal; do
            if is_package_installed "$anchor"; then
                if command -v apt-rdepends >/dev/null 2>&1; then
                    apt-rdepends "$anchor" 2>/dev/null \
                        | awk '/^[a-z0-9]/ {print $1}'
                else
                    apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
                        --no-breaks --no-replaces --no-enhances "$anchor" 2>/dev/null \
                        | awk '/^[a-z0-9]/ {print $1}'
                fi
            fi
        done
    } | LC_ALL=C sort -u
}

# Compute the safe XFCE/Xubuntu purge set: installed pkgs matching the patterns,
# minus anything in the GNOME dep closure. Prints package names, one per line,
# sorted unique. Conservative: if we're not sure, we don't purge.
compute_xfce_purge_set() {
    local patterns_match keep_pkgs
    patterns_match="$(dpkg-query -W -f='${Package}\n' 2>/dev/null \
        | grep -E "$AUTOLINUX_XFCE_PATTERN" \
        | LC_ALL=C sort -u)"

    [ -z "$patterns_match" ] && return 0

    keep_pkgs="$(_compute_gnome_dep_closure)"

    # Use temp files: comm misreads FIFOs from process substitution as unsorted.
    local pm_f kp_f
    pm_f="$(mktemp)"; kp_f="$(mktemp)"
    printf '%s\n' "$patterns_match" > "$pm_f"
    printf '%s\n' "$keep_pkgs"      > "$kp_f"
    LC_ALL=C comm -23 "$pm_f" "$kp_f"
    rm -f "$pm_f" "$kp_f"
}

# Print the subset of the GNOME-dep-closure that matches the XFCE pattern AND
# is actually installed. This is what stage 08 displays as "EXCLUDED" — only
# the packages that are real on this system, not every alternative apt walked.
compute_xfce_keep_audit() {
    _compute_gnome_dep_closure \
        | grep -E "$AUTOLINUX_XFCE_PATTERN" \
        | while IFS= read -r p; do
            is_package_installed "$p" && echo "$p"
          done \
        | LC_ALL=C sort -u
}

# Are we currently inside an XFCE session? (Used to abort destructive stages.)
inside_xfce_session() {
    [ "$(detect_de)" = "xfce" ]
}
