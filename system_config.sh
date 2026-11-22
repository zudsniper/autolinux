#!/bin/bash
# Configures system settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/net.sh
source "$SCRIPT_DIR/lib/net.sh"

# Parse command line arguments
YES_TO_ALL=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            YES_TO_ALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-y|--yes]"
            exit 1
            ;;
    esac
done

echo "Configuring system..."

# Ensure adequate swap configuration (≥8GB)
echo "Verifying swap configuration..."
ACTIVE_SWAP_COUNT=$(swapon --show | grep -v '^NAME' | wc -l)

if [ "$ACTIVE_SWAP_COUNT" -eq 0 ]; then
    echo "No active swap found. Creating 8GB swap file..."
    # Create 8GB swap file
    fallocate -l 8G /swap.img
    chmod 600 /swap.img
    mkswap /swap.img
    swapon /swap.img
    
    # Add to fstab if not already there
    if ! grep -q "/swap.img" /etc/fstab; then
        echo "/swap.img	none	swap	sw	0	0" >> /etc/fstab
    fi
    echo "✅ Created and enabled 8GB swap file."
else
    # Check existing swap configuration
    SWAP_INFO=$(swapon --show | grep -v '^NAME' | head -1)
    SWAP_NAME=$(echo "$SWAP_INFO" | awk '{print $1}')
    SWAP_TYPE=$(echo "$SWAP_INFO" | awk '{print $2}')
    SWAP_SIZE_STR=$(echo "$SWAP_INFO" | awk '{print $3}')
    
    echo "Found active swap: $SWAP_NAME ($SWAP_TYPE, $SWAP_SIZE_STR)"
    
    # Check if it's the expected swap file and if size needs adjustment
    if [ "$SWAP_NAME" = "/swap.img" ] && [ "$SWAP_TYPE" = "file" ]; then
        # Extract numeric value from size (e.g., "4G" -> "4")
        SIZE_VALUE_G=$(echo "$SWAP_SIZE_STR" | sed 's/[^0-9.]//g')
        
        # Check if size is adequate (should be ≥8GB)
        if awk -v val="$SIZE_VALUE_G" 'BEGIN { exit (val >= 8) ? 0 : 1 }'; then
            echo "✅ Swap file size is adequate ($SWAP_SIZE_STR)."
            
            # Verify fstab configuration
            if grep -q "/swap.img.*swap" /etc/fstab; then
                echo "✅ Swap file is properly configured in /etc/fstab."
            else
                echo "Adding swap file to /etc/fstab..."
                echo "/swap.img	none	swap	sw	0	0" >> /etc/fstab
                echo "✅ Added swap file to /etc/fstab."
            fi
        else
            echo "Swap file size ($SWAP_SIZE_STR) is too small. Resizing to 8GB..."
            
            # Disable current swap
            swapoff /swap.img
            
            # Resize swap file to 8GB
            fallocate -l 8G /swap.img
            mkswap /swap.img
            swapon /swap.img
            
            echo "✅ Resized swap file to 8GB."
        fi
    else
        echo "Found swap configuration: $SWAP_NAME ($SWAP_TYPE, $SWAP_SIZE_STR)"
        echo "Note: Using existing swap configuration. For optimal performance, consider using at least 8GB swap."
    fi
fi


# Network configuration: Wake-on-LAN (wired only) and an optional static
# address. The address is derived from the subnet the router actually serves
# (detected from the default route), never a hardcoded 192.168.1.x.
#
#   AUTOLINUX_STATIC_IP    auto (default) | no | <address>
#   AUTOLINUX_STATIC_HOST  host number used by "auto" (default 69 → x.y.z.69 on a /24)
#   AUTOLINUX_DNS          space-separated DNS servers (default "1.1.1.1 1.0.0.1")
function configure_networking() {
    echo
    echo "=== Network Configuration ==="

    local route IFACE GATEWAY CUR_ADDR PREFIX
    if ! route="$(net_default_route)"; then
        echo "❌ No IPv4 default route; skipping network configuration."
        return 0
    fi
    read -r IFACE GATEWAY CUR_ADDR PREFIX <<<"$route"
    echo "Default route: $IFACE via $GATEWAY (this machine: $CUR_ADDR/$PREFIX)"

    if [ "$YES_TO_ALL" != true ]; then
        read -r -p "Configure networking (Wake-on-LAN + static IP)? [y/N]: " CONFIGURE_NET
        [[ "${CONFIGURE_NET:-}" =~ ^[Yy]$ ]] || { echo "Skipping network configuration."; return 0; }
    fi

    # Wake-on-LAN only makes sense (and ethtool only succeeds) on wired NICs.
    if [ -e "/sys/class/net/$IFACE/device" ] && [ ! -d "/sys/class/net/$IFACE/wireless" ]; then
        if ethtool -s "$IFACE" wol g 2>/dev/null; then
            cat > /etc/systemd/system/wol.service <<UNIT
[Unit]
Description=Configure Wake-on-LAN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${IFACE} wol g

[Install]
WantedBy=multi-user.target
UNIT
            systemctl enable wol.service
            echo "✅ Wake-on-LAN enabled on $IFACE."
        else
            echo "⚠️  $IFACE does not support Wake-on-LAN; skipped."
        fi
    else
        echo "ℹ️  $IFACE is not a wired NIC; Wake-on-LAN skipped."
    fi

    # Pick the static address.
    local mode="${AUTOLINUX_STATIC_IP:-auto}" host="${AUTOLINUX_STATIC_HOST:-69}"
    local dns="${AUTOLINUX_DNS:-1.1.1.1 1.0.0.1}" STATIC_IP="" suggested gw_in
    [ "$mode" = "no" ] && { echo "Keeping DHCP (AUTOLINUX_STATIC_IP=no)."; return 0; }

    if suggested="$(net_host_in_subnet "$CUR_ADDR" "$PREFIX" "$host")"; then
        if [ "$suggested" != "$CUR_ADDR" ] && net_addr_in_use "$suggested" "$IFACE"; then
            echo "⚠️  $suggested is already in use on this network; suggesting the current lease instead."
            suggested="$CUR_ADDR"
        fi
    else
        suggested="$CUR_ADDR"
    fi
    [ "$mode" != "auto" ] && suggested="$mode"

    if [ "$YES_TO_ALL" = true ]; then
        STATIC_IP="$suggested"
    else
        read -r -p "Set a static IP? [y/N]: " CONFIGURE_STATIC
        [[ "${CONFIGURE_STATIC:-}" =~ ^[Yy]$ ]] || { echo "Keeping DHCP."; return 0; }
        read -r -p "Static IP [$suggested]: " STATIC_IP
        STATIC_IP="${STATIC_IP:-$suggested}"
        read -r -p "Gateway [$GATEWAY]: " gw_in
        GATEWAY="${gw_in:-$GATEWAY}"
    fi

    if ! [[ "$STATIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
        || [ "$(net_host_in_subnet "$STATIC_IP" "$PREFIX" 1)" != "$(net_host_in_subnet "$GATEWAY" "$PREFIX" 1)" ]; then
        echo "❌ $STATIC_IP is not in the gateway's subnet ($GATEWAY/$PREFIX); keeping DHCP."
        return 0
    fi

    echo "Static IP: $STATIC_IP/$PREFIX via $GATEWAY, DNS $dns"
    echo "   Tip: reserve $STATIC_IP for this machine in the router's DHCP settings so it never hands it out."

    local con
    if systemctl is-active --quiet NetworkManager && con="$(net_nm_connection "$IFACE")" && [ -n "$con" ]; then
        # Desktop: keep NetworkManager in charge so GNOME Settings stays accurate.
        local backup
        backup="/var/backups/autolinux-nm-$(echo "$con" | tr -c 'A-Za-z0-9_-' _)-$(date +%Y%m%d-%H%M%S).txt"
        nmcli -f ipv4 connection show "$con" > "$backup" 2>/dev/null || true
        nmcli connection modify "$con" \
            ipv4.method manual \
            ipv4.addresses "$STATIC_IP/$PREFIX" \
            ipv4.gateway "$GATEWAY" \
            ipv4.dns "$dns" \
            ipv4.ignore-auto-dns yes
        nmcli connection up "$con" >/dev/null
        echo "✅ Static IP set on NetworkManager connection '$con' (previous ipv4 settings: $backup)."
        echo "   Undo: nmcli con mod '$con' ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' ipv4.ignore-auto-dns no && nmcli con up '$con'"
    else
        # Server / no NetworkManager: netplan with networkd.
        local np=/etc/netplan/60-autolinux-static.yaml dns_list
        dns_list="${dns// /, }"
        [ -f "$np" ] && cp -a "$np" "$np.backup.$(date +%Y%m%d-%H%M%S)"
        cat > "$np" <<YAML
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}/${PREFIX}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${dns_list}]
YAML
        chmod 600 "$np"
        netplan apply
        echo "✅ Static IP written to $np (delete it and run 'netplan apply' to undo)."
    fi
}

# Call network configuration function
configure_networking

# Configure SSH server
systemctl enable ssh
systemctl start ssh

# Wayland is the default session; Ringboard and Tiling Shell both work on it.
# Older autolinux versions forced Xorg with WaylandEnable=false. Undo that
# (keeping a backup) instead of forcing anything.
GDM_CONF=/etc/gdm3/custom.conf
if [ -f "$GDM_CONF" ] && grep -qE '^\s*WaylandEnable\s*=\s*false' "$GDM_CONF"; then
    cp -a "$GDM_CONF" "$GDM_CONF.autolinux-backup.$(date +%Y%m%d-%H%M%S)"
    sed -i -E 's/^\s*WaylandEnable\s*=\s*false.*$/#WaylandEnable=false  (re-enabled Wayland: autolinux)/' "$GDM_CONF"
    echo "Re-enabled Wayland in $GDM_CONF (takes effect at next login)."
fi

# Configure sudoers for current user with NOPASSWD
CURRENT_USER=$(logname || whoami)
if [ "$CURRENT_USER" != "root" ]; then
    echo "Setting up passwordless sudo for user $CURRENT_USER..."
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$CURRENT_USER
    chmod 0440 /etc/sudoers.d/$CURRENT_USER
fi

echo "System configuration completed"