#!/bin/bash
# Configures system settings

set -e

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


# Network configuration
function configure_networking() {
    echo "\n=== Network Configuration ==="
    echo "This will configure Wake-on-LAN and static IP settings."
    
    if [ "$YES_TO_ALL" = true ]; then
        CONFIGURE_NET="y"
    else
        read -p "Do you want to configure networking (Wake-on-LAN + static IP)? [y/N]: " CONFIGURE_NET
    fi
    
    if [[ "$CONFIGURE_NET" =~ ^[Yy]$ ]]; then
        # Get network interface
        IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
        
        if [ -z "$IFACE" ]; then
            echo "❌ Could not detect network interface. Skipping network configuration."
            return
        fi
        
        echo "Detected network interface: $IFACE"
        
        # Configure WakeOnLAN
        echo "Configuring Wake-on-LAN..."
        ethtool -s ${IFACE} wol g
        
        # Create persistent WakeOnLAN config
        cat > /etc/systemd/system/wol.service << EOF
[Unit]
Description=Configure Wake-on-LAN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${IFACE} wol g

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable wol.service
        echo "✅ Wake-on-LAN configured."
        
        # Static IP configuration
        if [ "$YES_TO_ALL" = true ]; then
            CONFIGURE_STATIC="y"
            STATIC_IP="192.168.1.69"
            GATEWAY="192.168.1.1"
        else
            read -p "Do you want to configure a static IP? [y/N]: " CONFIGURE_STATIC
            if [[ "$CONFIGURE_STATIC" =~ ^[Yy]$ ]]; then
                read -p "Enter static IP address [192.168.1.69]: " STATIC_IP
                STATIC_IP=${STATIC_IP:-192.168.1.69}
                read -p "Enter gateway IP [192.168.1.1]: " GATEWAY
                GATEWAY=${GATEWAY:-192.168.1.1}
            fi
        fi
        
        if [[ "$CONFIGURE_STATIC" =~ ^[Yy]$ ]]; then
            echo "Configuring static IP: $STATIC_IP"
            
            # Set static IP with Cloudflare DNS
            cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${STATIC_IP}/24
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [1.1.1.1, 1.0.0.1]
EOF
            netplan apply
            echo "✅ Static IP configured: $STATIC_IP"
        else
            echo "Keeping DHCP configuration."
        fi
    else
        echo "Skipping network configuration."
    fi
}

# Call network configuration function
configure_networking

# Configure SSH server
systemctl enable ssh
systemctl start ssh

# Set X11 as default display manager
cat > /etc/gdm3/custom.conf << EOF
# GDM configuration storage

[daemon]
# Force the login screen to use Xorg
WaylandEnable=false

[security]

[xdmcp]

[chooser]

[debug]
EOF

# Configure sudoers for current user with NOPASSWD
CURRENT_USER=$(logname || whoami)
if [ "$CURRENT_USER" != "root" ]; then
    echo "Setting up passwordless sudo for user $CURRENT_USER..."
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$CURRENT_USER
    chmod 0440 /etc/sudoers.d/$CURRENT_USER
fi

echo "System configuration completed"