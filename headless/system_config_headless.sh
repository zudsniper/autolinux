#!/bin/bash
# Configures system settings for headless/server installations

set -e
echo "Configuring headless system..."

# Create swap if needed (16GB)
# Ensure a swap partition of 16-17GB on the OS drive is active and configured
echo "Verifying swap partition configuration..."
ACTIVE_SWAP_COUNT=$(swapon --show | grep -v '^NAME' | wc -l)

if [ "$ACTIVE_SWAP_COUNT" -eq 0 ]; then
    echo "Error: No active swap found. Please configure a swap partition of ~16-17GB on the OS drive." >&2
    exit 1
fi

ROOT_DEVICE_PATH=$(findmnt -n -o SOURCE /)
if [ -z "$ROOT_DEVICE_PATH" ]; then
    echo "Error: Could not determine root device path." >&2
    exit 1
fi

# Helper function to get a comparable disk identifier (e.g., sda, nvme0n1)
get_disk_identifier() {
    local dev_path="$1"
    # Resolve LVM or other mapped names to the underlying kernel device name if possible
    local kname
    kname=$(lsblk -no KNAME "$dev_path" | head -n1)
    if [ -z "$kname" ]; then # If KNAME is not found (e.g. already a base device)
        kname=$(basename "$dev_path")
    fi

    # Try to get parent kernel name (for partitions) or the name itself (for whole disks)
    local pkname
    pkname=$(lsblk -no PKNAME "/dev/$kname" 2>/dev/null)
    if [ -n "$pkname" ]; then
        echo "$pkname"
    else
        # If no PKNAME (e.g., it's a whole disk like /dev/sda, or nvme0n1), return the base name
        echo "$kname" | sed 's/[0-9]*$//' # Attempt to strip trailing partition numbers for consistency, e.g. nvme0n1p1 -> nvme0n1
    fi
}


ROOT_DISK_ID=$(get_disk_identifier "$ROOT_DEVICE_PATH")
if [ -z "$ROOT_DISK_ID" ]; then
    echo "Error: Could not determine root disk identifier from $ROOT_DEVICE_PATH." >&2
    exit 1
fi
echo "Root disk identifier: $ROOT_DISK_ID"

FOUND_CORRECT_SWAP=false
IFS_BAK=$IFS
IFS=$'\n' # Handle spaces in device names if any, though unlikely for swap
for line in $(swapon --show | grep -v '^NAME'); do
    IFS=$IFS_BAK # Restore IFS for read
    # Using awk to handle potentially varying whitespace
    SWAP_NAME=$(echo "$line" | awk '{print $1}')
    SWAP_TYPE=$(echo "$line" | awk '{print $2}')
    SWAP_SIZE_STR=$(echo "$line" | awk '{print $3}')

    if [ "$SWAP_TYPE" != "partition" ]; then
        echo "Skipping non-partition swap: $SWAP_NAME ($SWAP_TYPE)"
        continue
    fi

    # Size check (15.9G to 17.1G to be safe)
    SIZE_VALUE_G=$(echo "$SWAP_SIZE_STR" | sed 's/[gG]$//')
    IS_SIZE_CORRECT=$(awk -v val="$SIZE_VALUE_G" 'BEGIN { if (val >= 15.9 && val <= 17.1) { exit 0 } else { exit 1 } }')
    if ! $IS_SIZE_CORRECT; then
        echo "Skipping swap $SWAP_NAME: size $SWAP_SIZE_STR is not within 16-17GB range."
        continue
    fi

    SWAP_DISK_ID=$(get_disk_identifier "$SWAP_NAME")
    if [ -z "$SWAP_DISK_ID" ]; then
        echo "Warning: Could not determine disk identifier for swap $SWAP_NAME."
        continue
    fi
    echo "Swap $SWAP_NAME is on disk $SWAP_DISK_ID"

    if [ "$SWAP_DISK_ID" != "$ROOT_DISK_ID" ]; then
        echo "Skipping swap $SWAP_NAME: it is on disk $SWAP_DISK_ID, not on root disk $ROOT_DISK_ID."
        continue
    fi

    # Check /etc/fstab
    SWAP_UUID=$(blkid -s UUID -o value "$SWAP_NAME" 2>/dev/null)
    FSTAB_CONFIGURED=false
    if [ -n "$SWAP_UUID" ] && grep -q "UUID=$SWAP_UUID.*swap" /etc/fstab; then
        FSTAB_CONFIGURED=true
    elif grep -q "$SWAP_NAME.*swap" /etc/fstab; then
        FSTAB_CONFIGURED=true
    fi

    if ! $FSTAB_CONFIGURED; then
        echo "Skipping swap $SWAP_NAME: not correctly configured in /etc/fstab."
        continue
    fi

    echo "Success: Found correctly configured swap partition: $SWAP_NAME, Size: $SWAP_SIZE_STR, on root disk $ROOT_DISK_ID, and in /etc/fstab."
    FOUND_CORRECT_SWAP=true
    break # Found one, that's enough
done
IFS=$IFS_BAK # Restore IFS fully

if [ "$FOUND_CORRECT_SWAP" = false ]; then
    echo "Error: Could not find a correctly configured active swap partition." >&2
    echo "Requirements: type 'partition', size ~16-17GB, on the same disk as root filesystem, and listed in /etc/fstab." >&2
    exit 1
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

# Configure sudoers for current user with NOPASSWD
CURRENT_USER=$(logname || whoami)
if [ "$CURRENT_USER" != "root" ]; then
    echo "Setting up passwordless sudo for user $CURRENT_USER..."
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$CURRENT_USER
    chmod 0440 /etc/sudoers.d/$CURRENT_USER
fi

# Set default target to multi-user (console only, no GUI)
systemctl set-default multi-user.target

echo "Headless system configuration completed" 