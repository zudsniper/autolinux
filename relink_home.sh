#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to print colored section headers
print_header() {
    echo -e "${BOLD}${BLUE}=== $1 ===${RESET}"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${RESET}"
}

# Function to print information
print_info() {
    echo -e "${CYAN}ℹ $1${RESET}"
}

# Function to prompt for confirmation
confirm() {
    echo -e "${PURPLE}$1 [y/N]${RESET} "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Welcome
clear
echo -e "${BOLD}${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║   Home Directory Relinker for Ubuntu                  ║"
echo "║   Reconnect your /home partition after reinstall      ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

print_info "This script will help you relink your /home directory from a separate partition."
print_warning "This script should be run as the same user that owns the home directory on the separate partition."
print_warning "Proceed with caution. Backup any important data before continuing."
echo ""

# Check if script is run as root
if [ "$EUID" -eq 0 ]; then
    print_error "This script should NOT be run as root/sudo!"
    print_info "Please run it as your regular user (with sudo privileges)."
    exit 1
fi

# Confirm the user has sudo privileges
if ! sudo -v; then
    print_error "You need sudo privileges to run this script."
    exit 1
fi

print_success "Sudo privileges confirmed."

# Check for sufficient disk space
print_info "Checking available disk space..."
available_space=$(df -h / | awk 'NR==2 {print $4}')
print_info "Available space on / partition: $available_space"

# Step 1: Show available partitions
print_header "STEP 1: Identify Your Home Partition"

echo -e "Here's a list of partitions on your system:"
lsblk -f
echo ""
echo -e "And here's more detailed information:"
sudo fdisk -l | grep -E "^Disk /|^/dev/"
echo ""

# Get the partition from user
echo -e "${CYAN}Enter the partition containing your home directory (e.g., /dev/sda2):${RESET} "
read -r home_partition

# Validate partition exists
if [ ! -b "$home_partition" ]; then
    print_error "The partition $home_partition does not exist!"
    exit 1
fi

print_success "Selected partition: $home_partition"

# Step 2: Mount the partition temporarily
print_header "STEP 2: Temporarily Mount the Partition"

sudo mkdir -p /mnt/oldhome 2>/dev/null

if ! sudo mount "$home_partition" /mnt/oldhome; then
    print_error "Failed to mount $home_partition to /mnt/oldhome"
    exit 1
fi

print_success "Successfully mounted $home_partition to /mnt/oldhome"

# Step 3: Verify contents
print_header "STEP 3: Verify Partition Contents"

echo -e "Here are the top-level directories in the mounted partition:"
ls -la /mnt/oldhome

if [ ! -d "/mnt/oldhome/$(whoami)" ]; then
    print_warning "Your username '$(whoami)' doesn't have a directory on this partition."
    echo -e "Available user directories:"
    ls -la /mnt/oldhome | grep -E '^d' | awk '{print $9}'
    
    if ! confirm "Continue anyway? (Type 'y' to continue, any other key to abort)"; then
        sudo umount /mnt/oldhome
        print_info "Unmounted /mnt/oldhome. Script aborted."
        exit 1
    fi
else
    print_success "Found your home directory: /mnt/oldhome/$(whoami)"
fi

# Step 4: Check user IDs
print_header "STEP 4: Check User IDs"

current_uid=$(id -u)
old_uid=$(stat -c "%u" "/mnt/oldhome/$(whoami)" 2>/dev/null)

echo -e "Your current UID: ${BOLD}$current_uid${RESET}"
echo -e "UID of your old home directory: ${BOLD}$old_uid${RESET}"

if [ "$current_uid" != "$old_uid" ] && [ -n "$old_uid" ]; then
    print_warning "The UIDs don't match. You will need to update your current UID to match your old one."
    
    if confirm "Would you like to change your current UID to $old_uid? (Type 'y' to change, any other key to skip)"; then
        print_info "This will change your UID and may cause temporary issues."
        print_info "You might need to log out and back in after this script completes."
        
        uid_change=true
    else
        print_warning "Continuing without changing UID. This may cause permission issues."
        uid_change=false
    fi
else
    print_success "UIDs match or couldn't determine old UID. No changes needed."
    uid_change=false
fi

# Step 5: Configure fstab
print_header "STEP 5: Configure /etc/fstab"

# Get filesystem type
fs_type=$(lsblk -f "$home_partition" -o FSTYPE | tail -n 1 | xargs)
if [ -z "$fs_type" ]; then
    fs_type="ext4"  # Default to ext4 if we can't determine
    print_warning "Couldn't determine filesystem type, defaulting to ext4."
    echo -e "Available filesystem types: ext4, xfs, btrfs, etc."
    echo -e "${CYAN}Enter the filesystem type (or press Enter to use ext4):${RESET} "
    read -r input_fs_type
    if [ -n "$input_fs_type" ]; then
        fs_type="$input_fs_type"
    fi
else
    print_success "Filesystem type detected: $fs_type"
fi

# Get UUID for more reliable mounting
uuid=$(lsblk -f "$home_partition" -o UUID | tail -n 1 | xargs)
if [ -z "$uuid" ]; then
    print_warning "Couldn't determine UUID of partition. Will use device path instead."
    fstab_entry="$home_partition  /home  $fs_type  defaults  0  2"
else
    print_success "Partition UUID: $uuid"
    fstab_entry="UUID=$uuid  /home  $fs_type  defaults  0  2"
fi

echo -e "The following line will be added to /etc/fstab:"
echo -e "${BOLD}$fstab_entry${RESET}"

if confirm "Continue with this configuration? (Type 'y' to continue, any other key to abort)"; then
    # Backup fstab
    sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
    print_success "Created backup of /etc/fstab"
    
    # Check if there's already an entry for /home
    if grep -q " /home " /etc/fstab; then
        print_warning "Found existing /home entry in fstab."
        echo -e "Current entries:"
        grep " /home " /etc/fstab
        
        if confirm "Do you want to replace the existing /home entry? (Type 'y' to replace, any other key to abort)"; then
            sudo sed -i "s|.* /home .*|$fstab_entry|" /etc/fstab
            print_success "Replaced existing /home entry in /etc/fstab"
        else
            print_error "Cannot continue without updating fstab."
            sudo umount /mnt/oldhome
            exit 1
        fi
    else
        # Append to fstab
        echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
        print_success "Added new entry to /etc/fstab"
    fi
else
    sudo umount /mnt/oldhome
    print_info "Unmounted /mnt/oldhome. Script aborted."
    exit 1
fi

# Step 6: Change UID if necessary
if [ "$uid_change" = true ]; then
    print_header "STEP 6: Change User ID"
    
    print_warning "Changing UID requires logging out all sessions of this user."
    print_warning "Make sure to save all your work before proceeding."
    
    if confirm "Ready to change your UID to $old_uid? (Type 'y' to change, any other key to skip)"; then
        sudo usermod -u "$old_uid" "$(whoami)"
        print_success "Changed UID to $old_uid."
    else
        print_warning "Skipping UID change. This may cause permission issues."
    fi
fi

# Step 7: Prepare for remounting
print_header "STEP 7: Prepare for Remounting"

print_info "We will now:"
print_info "1. Move the current /home to /home.bak"
print_info "2. Create a new empty /home directory"
print_info "3. Mount your old /home partition"

if confirm "Continue with these operations? (Type 'y' to continue, any other key to abort)"; then
    # Unmount first
    sudo umount /mnt/oldhome
    print_success "Unmounted temporary mount point"
    
    # Check if /home.bak already exists
    if [ -d "/home.bak" ]; then
        print_warning "/home.bak already exists."
        timestamp=$(date +%Y%m%d%H%M%S)
        if confirm "Move existing /home.bak to /home.bak.$timestamp? (Type 'y' to move, any other key to abort)"; then
            sudo mv /home.bak "/home.bak.$timestamp"
            print_success "Moved existing /home.bak to /home.bak.$timestamp"
        else
            print_error "Cannot continue without addressing existing /home.bak"
            exit 1
        fi
    fi
    
    # Move, create, mount
    sudo mv /home /home.bak
    print_success "Moved current /home to /home.bak"
    
    sudo mkdir /home
    print_success "Created new empty /home directory"
    
    if ! sudo mount -a; then
        print_error "Failed to mount all filesystems from fstab."
        print_error "This is critical. Restoring original /home."
        sudo rmdir /home
        sudo mv /home.bak /home
        exit 1
    fi
    
    # Check if mount succeeded
    if mountpoint -q /home; then
        print_success "Successfully mounted your home partition to /home"
    else
        print_error "Failed to mount your home partition!"
        print_error "Restoring original /home."
        sudo rmdir /home
        sudo mv /home.bak /home
        exit 1
    fi
else
    sudo umount /mnt/oldhome
    print_info "Unmounted /mnt/oldhome. Script aborted."
    exit 1
fi

# Step 8: Final checks
print_header "STEP 8: Final Checks"

# List contents of new /home
echo -e "Contents of newly mounted /home:"
ls -la /home

# Verify user's home directory
if [ -d "/home/$(whoami)" ]; then
    print_success "Your home directory exists in the mounted partition."
    
    # Check if we can access some files
    if [ -r "/home/$(whoami)/.bashrc" ] || [ -r "/home/$(whoami)/.profile" ]; then
        print_success "Basic configuration files are accessible."
    else
        print_warning "Some configuration files might not be accessible. Check permissions."
    fi
else
    print_error "Your home directory doesn't exist or isn't accessible in the mounted partition."
    print_warning "You might need to create it manually or check permissions."
fi

# Final summary
print_header "SUMMARY"

print_success "The /home directory has been successfully relinked to your separate partition."
print_info "Your previous /home directory is backed up at /home.bak"
print_info "You should reboot your system to ensure all services use the new /home correctly."

if [ "$uid_change" = true ]; then
    print_warning "You changed your UID. You MUST reboot your system now."
fi

if confirm "Would you like to reboot now? (Type 'y' to reboot, any other key to exit)"; then
    print_info "Rebooting system..."
    sudo reboot
else
    print_info "Please reboot your system manually when convenient."
    print_info "You can use: sudo reboot"
fi

# Exit with success
exit 0