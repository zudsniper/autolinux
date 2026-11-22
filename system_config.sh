#!/bin/bash
# system_config.sh — base system settings for an autolinux machine.
#
#   sudo ./system_config.sh                              # swap, SSH, Wayland, sudo; network untouched
#   sudo ./system_config.sh --static-ip 192.168.50.20    # also pin this address (router DNS kept)
#   sudo ./system_config.sh --static-ip 10.0.0.5/24 --gateway 10.0.0.1 --dns 1.1.1.1,9.9.9.9
#   sudo ./system_config.sh --wol                        # also enable Wake-on-LAN (wired NIC)
#   ./system_config.sh --dry-run                         # show what would change
#
# Networking is never touched unless a network flag is given.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AUTOLINUX_REPO_DIR="${AUTOLINUX_REPO_DIR:-$SCRIPT_DIR}"
source "$SCRIPT_DIR/lib/log.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/safety.sh"
source "$SCRIPT_DIR/lib/pkg.sh"
source "$SCRIPT_DIR/lib/net.sh"

usage() {
    cat <<EOF
Usage: sudo ./system_config.sh [flags]

Always (each step is skipped when already in place):
  swap ≥ 8 GB, SSH server enabled, Wayland re-enabled if an old run forced
  Xorg, passwordless sudo for the invoking user.

Network (only with these flags):
  --static-ip <ip[/prefix]>  Pin this IPv4 address on the default-route interface.
                             Prefix defaults to the current subnet's.
  --gateway <ip>             Gateway for --static-ip (default: current default route)
  --dns <ip[,ip...]>         DNS for --static-ip (default: the servers DHCP hands out now,
                             i.e. usually the router)
  --wol                      Enable Wake-on-LAN on the default wired interface

General:
  -y, --yes                  Don't ask for confirmation
  -n, --dry-run              Show the plan and every command, change nothing
  -h, --help                 This message
EOF
}

export AUTOLINUX_DRY_RUN="${AUTOLINUX_DRY_RUN:-0}" AUTOLINUX_YES="${AUTOLINUX_YES:-0}"
STATIC_IP="" GATEWAY_ARG="" DNS_ARG="" WOL=0

need_val() { if [ "$#" -lt 2 ] || [ -z "$2" ] || [ "${2:0:1}" = "-" ]; then log_die "$1 needs a value"; fi; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --static-ip|--gateway|--dns) need_val "$@" ;;
    esac
    case "$1" in
        --static-ip)    STATIC_IP="$2"; shift 2 ;;
        --gateway)      GATEWAY_ARG="$2"; shift 2 ;;
        --dns)          DNS_ARG="$2"; shift 2 ;;
        --wol)          WOL=1; shift ;;
        -y|--yes)       AUTOLINUX_YES=1; shift ;;
        -n|--dry-run)   AUTOLINUX_DRY_RUN=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) log_error "unknown flag: $1"; usage >&2; exit 2 ;;
    esac
done

if [ -n "$GATEWAY_ARG$DNS_ARG" ] && [ -z "$STATIC_IP" ]; then
    log_die "--gateway/--dns only apply together with --static-ip"
fi
if [ -n "$STATIC_IP" ]; then
    net_valid_ip "${STATIC_IP%/*}" || log_die "--static-ip: '$STATIC_IP' is not an IPv4 address"
    if [[ "$STATIC_IP" == */* ]] && ! [[ "${STATIC_IP#*/}" =~ ^([89]|[12][0-9]|30)$ ]]; then
        log_die "--static-ip: prefix must be /8–/30"
    fi
fi
[ -z "$GATEWAY_ARG" ] || net_valid_ip "$GATEWAY_ARG" || log_die "--gateway: '$GATEWAY_ARG' is not an IPv4 address"
for d in ${DNS_ARG//,/ }; do net_valid_ip "$d" || log_die "--dns: '$d' is not an IPv4 address"; done

[ "$AUTOLINUX_DRY_RUN" = "1" ] || require_root

# ---------- step runner + summary ----------
_c() { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && printf '\033[%sm' "$1"; }
SUMMARY=() STATUS="" DETAIL=""
STEPS=(swap ssh wayland sudo wol static_ip)
TITLES=("Swap" "SSH server" "Wayland session" "Passwordless sudo" "Wake-on-LAN" "Static IP")

run_steps() {
    local i n=${#STEPS[@]}
    for i in "${!STEPS[@]}"; do
        printf '\n%s[%d/%d]%s %s%s%s\n' "$(_c '1;34')" $((i+1)) "$n" "$(_c 0)" "$(_c 1)" "${TITLES[$i]}" "$(_c 0)"
        STATUS="" DETAIL=""
        if "step_${STEPS[$i]}"; then :; else STATUS=failed; fi
        SUMMARY+=("${STATUS:-unchanged}|${TITLES[$i]}|$DETAIL")
    done
}

print_summary() {
    local row status title detail sym color failed=0
    printf '\n%s━━━ Summary ━━━%s\n' "$(_c '1;34')" "$(_c 0)"
    for row in "${SUMMARY[@]}"; do
        IFS='|' read -r status title detail <<<"$row"
        case "$status" in
            changed)   sym="✔"; color='0;32' ;;
            unchanged) sym="•"; color='0;36' ;;
            skipped)   sym="–"; color='0;90' ;;
            *)         sym="✘"; color='0;31'; failed=1 ;;
        esac
        [ "$AUTOLINUX_DRY_RUN" = "1" ] && [ "$status" = changed ] && status="would change"
        printf '  %s%s %-18s%s %-13s %s\n' "$(_c "$color")" "$sym" "$title" "$(_c 0)" "$status" "$detail"
    done
    echo
    return $failed
}

# Write a file (or show it in dry-run). Usage: write_file <path> <mode> <<<content
write_file() {
    local path=$1 mode=$2 content
    content="$(cat)"
    if [ "$AUTOLINUX_DRY_RUN" = "1" ]; then
        log_dryrun "write $path (mode $mode):"
        printf '%s\n' "$content" | sed 's/^/      /'
        return 0
    fi
    printf '%s\n' "$content" > "$path" && chmod "$mode" "$path"
}

# ---------- steps ----------
SWAP_FILE=/swap.img SWAP_GB=8

_swap_fstab() {
    grep -qE "^[[:space:]]*${SWAP_FILE}[[:space:]]" /etc/fstab && return 0
    if [ "$AUTOLINUX_DRY_RUN" = "1" ]; then log_dryrun "append '$SWAP_FILE none swap sw 0 0' to /etc/fstab"; return 0; fi
    printf '%s\tnone\tswap\tsw\t0\t0\n' "$SWAP_FILE" >> /etc/fstab
}

step_swap() {
    local name="" type="" size=0 want=$(( SWAP_GB * 1024 * 1024 * 1024 ))
    read -r name type size < <(swapon --show=NAME,TYPE,SIZE --bytes --noheadings 2>/dev/null | head -1)
    if [ -z "$name" ]; then
        log_info "no active swap; creating ${SWAP_GB} GB $SWAP_FILE"
        { run_or_dry fallocate -l "${SWAP_GB}G" "$SWAP_FILE" && run_or_dry chmod 600 "$SWAP_FILE" \
            && run_or_dry mkswap "$SWAP_FILE" && run_or_dry swapon "$SWAP_FILE" && _swap_fstab; } || return 1
        STATUS=changed DETAIL="created ${SWAP_GB} GB $SWAP_FILE"
        return 0
    fi
    local have_gb=$(( (size + 512*1024*1024) / 1024 / 1024 / 1024 ))
    # mkswap reserves a page, so allow a little slack under the target.
    if [ "$name" = "$SWAP_FILE" ] && [ "$type" = file ] && [ "$size" -lt $(( want - 64*1024*1024 )) ]; then
        log_info "$SWAP_FILE is ${have_gb} GB; growing to ${SWAP_GB} GB"
        { run_or_dry swapoff "$SWAP_FILE" && run_or_dry fallocate -l "${SWAP_GB}G" "$SWAP_FILE" \
            && run_or_dry mkswap "$SWAP_FILE" && run_or_dry swapon "$SWAP_FILE" && _swap_fstab; } || return 1
        STATUS=changed DETAIL="grew $SWAP_FILE ${have_gb} → ${SWAP_GB} GB"
        return 0
    fi
    if [ "$name" = "$SWAP_FILE" ]; then _swap_fstab || return 1; fi
    log_success "swap: $name ($type, ${have_gb} GB)"
    DETAIL="$name, ${have_gb} GB"
    if [ "$have_gb" -lt "$SWAP_GB" ]; then DETAIL+=" (below ${SWAP_GB} GB but not $SWAP_FILE; left alone)"; fi
    return 0
}

step_ssh() {
    if ! is_package_installed openssh-server; then
        apt_install openssh-server || return 1
        STATUS=changed
    fi
    # Ubuntu ≥ 22.10 starts sshd on demand through ssh.socket; either is fine.
    local u
    for u in ssh.socket ssh.service; do
        if is_service_enabled "$u" && is_service_active "$u"; then
            log_success "SSH is enabled and listening ($u)"
            DETAIL="$u enabled, active"
            return 0
        fi
    done
    u=ssh.service
    systemctl list-unit-files ssh.socket >/dev/null 2>&1 && u=ssh.socket
    run_or_dry systemctl enable --now "$u" || return 1
    STATUS=changed DETAIL="$u enabled + started"
}

step_wayland() {
    local conf=/etc/gdm3/custom.conf
    if [ ! -f "$conf" ] || ! grep -qE '^\s*WaylandEnable\s*=\s*false' "$conf"; then
        log_success "Wayland is not disabled in GDM"
        DETAIL="not forced off"
        return 0
    fi
    run_or_dry cp -a "$conf" "$conf.autolinux-backup.$(date +%Y%m%d-%H%M%S)" || return 1
    run_or_dry sed -i -E 's/^\s*WaylandEnable\s*=\s*false.*$/#WaylandEnable=false  (re-enabled Wayland: autolinux)/' "$conf" || return 1
    STATUS=changed DETAIL="re-enabled (next login)"
}

step_sudo() {
    local user file line
    user="$(real_user)"
    if [ -z "$user" ] || [ "$user" = root ]; then
        STATUS=skipped DETAIL="no non-root invoking user"
        log_skip "$DETAIL"
        return 0
    fi
    file="/etc/sudoers.d/$user" line="$user ALL=(ALL) NOPASSWD: ALL"
    # Ask sudo itself, so any equivalent existing rule counts (spacing,
    # (ALL:ALL), a group rule, ...).
    local have=1
    if is_root; then
        sudo -l -U "$user" 2>/dev/null | grep -qE 'NOPASSWD:[[:space:]]*ALL' && have=0
    elif [ "$user" = "$(id -un)" ]; then
        sudo -n true 2>/dev/null && have=0
    fi
    if [ "$have" = 0 ]; then
        log_success "$user already has passwordless sudo"
        DETAIL="$user"
        return 0
    fi
    if [ "$AUTOLINUX_DRY_RUN" = "1" ]; then
        log_dryrun "install '$line' as $file (0440)"
    else
        local tmp; tmp="$(mktemp)"
        printf '%s\n' "$line" > "$tmp"
        if ! visudo -cqf "$tmp"; then rm -f "$tmp"; log_error "generated sudoers line failed validation"; return 1; fi
        install -m 0440 -o root -g root "$tmp" "$file" || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
    fi
    STATUS=changed DETAIL="$user"
}

# Default route, read once and shared by the network steps.
IFACE="" CUR_GW="" CUR_ADDR="" CUR_PREFIX=""
_load_route() {
    [ -n "$IFACE" ] && return 0
    local r; r="$(net_default_route)" || return 1
    read -r IFACE CUR_GW CUR_ADDR CUR_PREFIX <<<"$r"
}

step_wol() {
    if [ "$WOL" != 1 ]; then
        STATUS=skipped DETAIL="pass --wol to enable"
        log_skip "$DETAIL"
        return 0
    fi
    _load_route || { log_error "no IPv4 default route"; return 1; }
    if [ ! -e "/sys/class/net/$IFACE/device" ] || [ -d "/sys/class/net/$IFACE/wireless" ]; then
        log_error "$IFACE is not a wired NIC; Wake-on-LAN needs Ethernet"
        DETAIL="$IFACE is not wired"
        return 1
    fi
    local info; info="$(ethtool "$IFACE" 2>/dev/null)"
    if grep -qE '^\s*Wake-on:\s*g' <<<"$info" && systemctl is-enabled --quiet wol.service 2>/dev/null; then
        log_success "Wake-on-LAN already on for $IFACE"
        DETAIL="$IFACE"
        return 0
    fi
    if ! grep -q 'Supports Wake-on' <<<"$info" && ! is_root; then
        log_warning "ethtool needs root to report Wake-on-LAN support"
        log_dryrun "ethtool -s $IFACE wol g  (+ wol.service)"
        STATUS=changed DETAIL="$IFACE (support unverified without root)"
        return 0
    fi
    if ! grep -qE '^\s*Supports Wake-on:.*g' <<<"$info"; then
        log_error "$IFACE does not support magic-packet Wake-on-LAN"
        DETAIL="unsupported on $IFACE"
        return 1
    fi
    run_or_dry ethtool -s "$IFACE" wol g || return 1
    write_file /etc/systemd/system/wol.service 0644 <<UNIT || return 1
[Unit]
Description=Enable Wake-on-LAN on ${IFACE} (autolinux)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${IFACE} wol g

[Install]
WantedBy=multi-user.target
UNIT
    { run_or_dry systemctl daemon-reload && run_or_dry systemctl enable wol.service; } || return 1
    STATUS=changed DETAIL="$IFACE (persisted via wol.service)"
}

step_static_ip() {
    if [ -z "$STATIC_IP" ]; then
        STATUS=skipped DETAIL="DHCP left as-is (pass --static-ip to pin one)"
        log_skip "$DETAIL"
        return 0
    fi
    _load_route || { log_error "no IPv4 default route to configure"; return 1; }

    local ip="${STATIC_IP%/*}" prefix="$CUR_PREFIX" gw="${GATEWAY_ARG:-$CUR_GW}" dns
    [[ "$STATIC_IP" == */* ]] && prefix="${STATIC_IP#*/}"
    if [ "$(net_host_in_subnet "$ip" "$prefix" 1)" != "$(net_host_in_subnet "$gw" "$prefix" 1)" ]; then
        log_error "$ip/$prefix is not in the same subnet as gateway $gw"
        DETAIL="$ip not in $gw's subnet"
        return 1
    fi
    if [ "$ip" != "$CUR_ADDR" ] && net_addr_in_use "$ip" "$IFACE"; then
        log_error "$ip already answers on the network; pick a free address"
        DETAIL="$ip is in use"
        return 1
    fi

    # Keep the DNS servers DHCP currently hands out (normally the router)
    # unless --dns was given; a manual IPv4 method would otherwise drop them.
    if [ -n "$DNS_ARG" ]; then
        dns="${DNS_ARG//,/ }"
    else
        dns="$(net_current_dns "$IFACE")"
        [ -n "$dns" ] || dns="$gw"
    fi
    log_info "$IFACE: $CUR_ADDR/$CUR_PREFIX (DHCP) → $ip/$prefix via $gw, DNS $dns"

    local con=""
    if systemctl is-active --quiet NetworkManager && con="$(net_nm_connection "$IFACE")" && [ -n "$con" ]; then
        # Desktop: keep NetworkManager in charge so GNOME Settings stays accurate.
        local backup
        backup="/var/backups/autolinux-nm-$(printf '%s' "$con" | tr -c 'A-Za-z0-9_-' _)-$(date +%Y%m%d-%H%M%S).txt"
        [ "$AUTOLINUX_DRY_RUN" = "1" ] || nmcli -f ipv4 connection show "$con" > "$backup" 2>/dev/null || true
        run_or_dry nmcli connection modify "$con" ipv4.method manual ipv4.addresses "$ip/$prefix" \
            ipv4.gateway "$gw" ipv4.dns "$dns" || return 1
        run_or_dry nmcli connection up "$con" || return 1
        STATUS=changed DETAIL="$ip/$prefix on '$con'"
        log_info "undo: nmcli con mod '$con' ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' && nmcli con up '$con'"
        [ "$AUTOLINUX_DRY_RUN" = "1" ] || log_info "previous ipv4 settings saved to $backup"
    else
        local np=/etc/netplan/60-autolinux-static.yaml
        write_file "$np" 0600 <<YAML || return 1
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${ip}/${prefix}
      routes:
        - to: default
          via: ${gw}
      nameservers:
        addresses: [${dns// /, }]
YAML
        run_or_dry netplan apply || return 1
        STATUS=changed DETAIL="$ip/$prefix via netplan"
        log_info "undo: rm $np && netplan apply"
    fi
    log_info "tip: reserve $ip for this machine in the router's DHCP settings"
}

# ---------- main ----------
printf '\n%s autolinux · system configuration %s\n\n' "$(_c '1;7;34')" "$(_c 0)"
printf '  %-9s %s\n' host "$(hostname)" user "$(real_user)" \
    mode "$([ "$AUTOLINUX_DRY_RUN" = 1 ] && echo 'dry-run (nothing will change)' || echo apply)"
if _load_route; then
    printf '  %-9s %s via %s (%s/%s, DNS %s)\n' network "$IFACE" "$CUR_GW" "$CUR_ADDR" "$CUR_PREFIX" \
        "$(net_current_dns "$IFACE" | sed 's/^$/?/')"
fi
net_plan="leave as-is"
[ -n "$STATIC_IP" ] && net_plan="static $STATIC_IP${GATEWAY_ARG:+ via $GATEWAY_ARG}, DNS ${DNS_ARG:-kept from DHCP}"
[ "$WOL" = 1 ] && net_plan+=" + Wake-on-LAN"
printf '  %-9s %s\n' "net plan" "$net_plan"

if [ "$AUTOLINUX_DRY_RUN" != "1" ] && [ -n "$STATIC_IP" ] && [ "$AUTOLINUX_YES" != "1" ]; then
    echo
    log_confirm "Changing the IP may briefly drop the connection (and SSH sessions). Continue?" || exit 1
fi

run_steps
print_summary
