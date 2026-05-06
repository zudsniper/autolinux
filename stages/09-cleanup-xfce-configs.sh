# shellcheck shell=bash
# Stage 09: archive leftover XFCE user configs.
# Moves ~/.config/xfce4/ and ~/.cache/sessions/xfce4* into ~/.config/autolinux-backup/<ts>/.

s09_detect() {
    local user home
    user="$(real_user)"
    home="$(real_home "$user")"
    [ -z "$home" ] && return 0
    [ ! -e "$home/.config/xfce4" ]
}

s09_precheck() { return 0; }

s09_execute() {
    local user home backup_dir ts
    user="$(real_user)"
    home="$(real_home "$user")"
    if [ -z "$home" ] || [ ! -d "$home" ]; then
        log_warning "could not resolve home for user '$user' — skipping"
        return 0
    fi
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$home/.config/autolinux-backup/xfce4-$ts"

    if [ ! -e "$home/.config/xfce4" ]; then
        log_skip "no $home/.config/xfce4 to archive"
        return 0
    fi

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "mkdir -p $backup_dir"
        log_dryrun "mv $home/.config/xfce4 $backup_dir/xfce4"
        return 0
    fi

    mkdir -p "$backup_dir"
    mv "$home/.config/xfce4" "$backup_dir/xfce4"
    chown -R "$user:$user" "$home/.config/autolinux-backup" 2>/dev/null || true

    state_array_append config_backups "$backup_dir/xfce4"
    log_success "archived $home/.config/xfce4 to $backup_dir/xfce4"

    # Also: stale autostart entries pointing at xfce binaries, if any.
    local autostart="$home/.config/autostart"
    if [ -d "$autostart" ]; then
        find "$autostart" -maxdepth 1 -type f -name '*.desktop' \
            -exec grep -l 'xfce4-\|/xfce4' {} \; 2>/dev/null | while read -r f; do
                [ -n "$f" ] || continue
                log_info "removing stale autostart referencing xfce: $(basename "$f")"
                mv "$f" "$backup_dir/$(basename "$f")"
            done
    fi
}

s09_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    s09_detect
}
