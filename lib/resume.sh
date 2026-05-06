# shellcheck shell=bash
# Resume hook installation/removal. Two layers, both pointing to the same
# wrapper at /usr/local/bin/autolinux-resume.
#
# Layer 1: ~/.config/autostart/autolinux-resume.desktop  (primary)
# Layer 2: /etc/systemd/system/autolinux-resume.service  (fallback)
#
# Both are idempotent. install/uninstall functions don't fail if already
# installed/uninstalled.

if [ -n "${_AUTOLINUX_RESUME_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_RESUME_SH_LOADED=1

AUTOLINUX_RESUME_BIN=/usr/local/bin/autolinux-resume
AUTOLINUX_SYSTEMD_UNIT=/etc/systemd/system/autolinux-resume.service

# We need to know where the repo lives so the resume hook can re-invoke bootstrap.sh.
# Caller sets AUTOLINUX_REPO_DIR; bootstrap.sh exports it.
_resume_autostart_path() {
    local user="$1" home
    home="$(real_home "$user")"
    echo "$home/.config/autostart/autolinux-resume.desktop"
}

_resume_write_wrapper() {
    local repo="$1" user="$2"
    local content
    content=$(cat <<EOF
#!/bin/bash
# autolinux resume wrapper — installed by lib/resume.sh.
# Re-invokes bootstrap.sh after a reboot-required stage.

set -u

REPO_DIR="$repo"
USER_NAME="$user"
STATE_FILE="${AUTOLINUX_STATE_DIR:-/var/lib/autolinux}/state.json"

# Self-removal if state says we are done.
if [ -r "\$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
    status="\$(jq -r '.status // empty' < "\$STATE_FILE" 2>/dev/null)"
    if [ "\$status" = "done" ]; then
        rm -f "\$(getent passwd "\$USER_NAME" | cut -d: -f6)/.config/autostart/autolinux-resume.desktop" 2>/dev/null
        systemctl disable --now autolinux-resume.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/autolinux-resume.service
        rm -f "\$0"
        exit 0
    fi
fi

# Wait for the session to settle.
sleep 8

# Pick a terminal — prefer kitty if installed, else gnome-terminal, else xterm.
TERM_CMD=""
for cand in /usr/local/bin/kitty /usr/bin/kitty /usr/bin/gnome-terminal /usr/bin/xterm; do
    if [ -x "\$cand" ]; then TERM_CMD="\$cand"; break; fi
done

CMD="cd \\"\$REPO_DIR\\" && sudo -E ./bootstrap.sh --resume; echo; echo 'Press enter to close.'; read"

if [ -n "\$TERM_CMD" ]; then
    case "\$TERM_CMD" in
        *kitty)         exec "\$TERM_CMD" --hold bash -lc "\$CMD" ;;
        *gnome-terminal) exec "\$TERM_CMD" -- bash -lc "\$CMD" ;;
        *xterm)         exec "\$TERM_CMD" -hold -e bash -lc "\$CMD" ;;
    esac
fi

# Headless / no terminal — just run it (output goes to journal).
bash -lc "\$CMD"
EOF
)
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "write $AUTOLINUX_RESUME_BIN ($(echo "$content" | wc -l) lines)"
        return 0
    fi
    printf '%s\n' "$content" > "$AUTOLINUX_RESUME_BIN"
    chmod 0755 "$AUTOLINUX_RESUME_BIN"
}

_resume_write_autostart() {
    local user="$1"
    local home autostart_dir desktop_path
    home="$(real_home "$user")"
    autostart_dir="$home/.config/autostart"
    desktop_path="$autostart_dir/autolinux-resume.desktop"

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "create autostart entry $desktop_path"
        return 0
    fi
    mkdir -p "$autostart_dir"
    cat > "$desktop_path" <<EOF
[Desktop Entry]
Type=Application
Name=autolinux resume
Exec=$AUTOLINUX_RESUME_BIN
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
Terminal=false
Comment=Resume the autolinux migration on next login
EOF
    chown -R "$user:$user" "$home/.config/autostart" 2>/dev/null || true
}

_resume_write_systemd_unit() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "write $AUTOLINUX_SYSTEMD_UNIT"
        return 0
    fi
    cat > "$AUTOLINUX_SYSTEMD_UNIT" <<EOF
[Unit]
Description=autolinux migration resume (fallback to autostart)
After=graphical.target
ConditionPathExists=$AUTOLINUX_RESUME_BIN

[Service]
Type=oneshot
ExecStart=$AUTOLINUX_RESUME_BIN
RemainAfterExit=no

[Install]
WantedBy=graphical.target
EOF
    systemctl daemon-reload
    systemctl enable autolinux-resume.service >/dev/null 2>&1 || true
}

resume_install_hooks() {
    local repo="$1" user="$2"
    log_info "installing resume hooks for user=$user repo=$repo"
    _resume_write_wrapper       "$repo" "$user"
    _resume_write_autostart     "$user"
    _resume_write_systemd_unit
}

resume_remove_hooks() {
    local user="$1"
    local home autostart_path
    home="$(real_home "$user")"
    autostart_path="$home/.config/autostart/autolinux-resume.desktop"

    log_info "removing resume hooks"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "rm $autostart_path"
        log_dryrun "systemctl disable --now autolinux-resume.service"
        log_dryrun "rm $AUTOLINUX_SYSTEMD_UNIT $AUTOLINUX_RESUME_BIN"
        return 0
    fi
    rm -f "$autostart_path"
    if [ -e "$AUTOLINUX_SYSTEMD_UNIT" ]; then
        systemctl disable --now autolinux-resume.service >/dev/null 2>&1 || true
        rm -f "$AUTOLINUX_SYSTEMD_UNIT"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    rm -f "$AUTOLINUX_RESUME_BIN"
}
