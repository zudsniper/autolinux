# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Personal monitoring scripts pulled from zudsniper's gists. They need their
# own config (Discord webhook) after install, so they are opt-in.
MOD_DESC="Discord startup ping + disk-usage monitor services (gists)"
MOD_GROUP="extras"
MOD_PROFILES=""
mod_detect() { is_service_enabled discord-startup.service && is_service_enabled disk-monitor.service; }
mod_install() {
    apt_install_lean python3 dconf-cli || return 1
    local u; u="$(real_user)"
    run_or_dry curl -fsSL -o /usr/local/bin/discord.sh https://raw.githubusercontent.com/fieu/discord.sh/master/discord.sh || return 1
    run_or_dry curl -fsSL -o /usr/local/bin/startup_notification.sh https://gist.githubusercontent.com/zudsniper/cac1d22e06d57bcb2b1208ed3ce5400e/raw/startup_notification.sh || return 1
    run_or_dry curl -fsSL -o /usr/local/bin/disk_monitor.py https://gist.githubusercontent.com/zudsniper/2283b66f964b134e7a75c7ad0a045dc5/raw/disk_monitor.py || return 1
    run_or_dry chmod +x /usr/local/bin/discord.sh /usr/local/bin/startup_notification.sh /usr/local/bin/disk_monitor.py
    cat > /etc/systemd/system/discord-startup.service <<UNIT
[Unit]
Description=Discord Startup Notification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/startup_notification.sh
User=$u

[Install]
WantedBy=multi-user.target
UNIT
    cat > /etc/systemd/system/disk-monitor.service <<UNIT
[Unit]
Description=Disk Usage Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/disk_monitor.py
User=$u
Restart=always
RestartSec=3600

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable discord-startup.service disk-monitor.service
}
