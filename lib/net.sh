# shellcheck shell=bash
# Network helpers for system_config.sh: derive a static address from the
# subnet the router actually hands out, instead of assuming 192.168.1.0/24.

if [ -n "${_AUTOLINUX_NET_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_NET_SH_LOADED=1

ip_to_int() {
    local IFS=. a b c d
    read -r a b c d <<<"$1"
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

int_to_ip() {
    local n=$1
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

# net_pick_default_route  (reads `ip -4 route show default` on stdin)
# → "<iface> <gateway>" for the lowest-metric route.
net_pick_default_route() {
    awk '{
        m = 0; dev = ""; via = ""
        for (i = 1; i <= NF; i++) {
            if ($i == "metric") m = $(i+1)
            if ($i == "dev")    dev = $(i+1)
            if ($i == "via")    via = $(i+1)
        }
        if (dev != "" && via != "") print m, dev, via
    }' | sort -n | head -1 | cut -d' ' -f2-
}

# net_default_route → "<iface> <gateway> <address> <prefix>", or fails.
net_default_route() {
    local iface gw addr
    read -r iface gw < <(ip -4 route show default 2>/dev/null | net_pick_default_route)
    [ -n "${iface:-}" ] && [ -n "${gw:-}" ] || return 1
    addr="$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}')"
    [ -n "$addr" ] || return 1
    echo "$iface $gw ${addr%/*} ${addr#*/}"
}

# net_host_in_subnet <any-ip-in-subnet> <prefix> <host-number>
# → that host number inside the same subnet. Fails when it would be the
# network or broadcast address, or doesn't fit in the subnet.
net_host_in_subnet() {
    local ip=$1 prefix=$2 host=$3 base mask size
    [ "$prefix" -ge 1 ] && [ "$prefix" -le 30 ] || return 1
    size=$(( 1 << (32 - prefix) ))
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    base=$(( $(ip_to_int "$ip") & mask ))
    [ "$host" -ge 1 ] && [ "$host" -lt $(( size - 1 )) ] || return 1
    int_to_ip $(( base + host ))
}

# net_addr_in_use <ip> <iface> — true if another machine answers for it.
# The ping also populates the ARP cache, which catches hosts that drop ICMP.
net_addr_in_use() {
    local ip=$1 iface=$2
    ping -c 1 -W 1 -I "$iface" "$ip" >/dev/null 2>&1 && return 0
    ip neigh show "$ip" dev "$iface" 2>/dev/null | grep -qE 'REACHABLE|STALE|DELAY|PROBE'
}

# net_nm_connection <iface> → name of its active NetworkManager connection.
net_nm_connection() {
    nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
        | awk -F: -v d="$1" '$NF == d { NF--; print; exit }' OFS=:
}
