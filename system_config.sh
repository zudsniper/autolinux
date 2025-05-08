#!/bin/bash
# Configures system settings

set -e
echo "Configuring system..."

# Create swap if needed (16GB)
if [ $(swapon --show | wc -l) -eq 0 ]; then
    echo "Creating 16GB swap file..."
    fallocate -l 16G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Configure WakeOnLAN
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
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

# Set static IP 192.168.1.69 with Cloudflare DNS
cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - 192.168.1.69/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 1.0.0.1]
EOF
netplan apply

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

echo "System configuration completed"