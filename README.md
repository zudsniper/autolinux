# Ubuntu 24.10 Auto-Configuration Scripts

A complete automation suite for setting up Ubuntu 24.10 with a custom desktop environment, applications, and system configurations. This project automates the entire process from OS installation to fully configured desktop environment.

## 🎯 Project Overview

This collection of scripts transforms a fresh Ubuntu 24.10 installation into a fully configured development and productivity workstation with:
- Custom GNOME desktop environment with extensions
- Development tools (VS Code, Cursor, Docker, etc.)
- Gaming and entertainment applications
- System hardening and optimizations
- Static IP configuration with Wake-on-LAN

## 📋 Table of Contents

1. [Prerequisites & Requirements](#prerequisites--requirements)
2. [Installation Order](#installation-order)
3. [Script Descriptions](#script-descriptions)
4. [Dangerous Operations & Warnings](#dangerous-operations--warnings)
5. [Safe Configuration Options](#safe-configuration-options)
6. [Headless Server Installation](#headless-server-installation)
7. [Troubleshooting](#troubleshooting)

## 🔧 Prerequisites & Requirements

### Hardware Requirements
- **Disk Space**: Minimum 100GB for root partition + 16-17GB swap partition
- **RAM**: 8GB minimum, 16GB recommended
- **Network**: Ethernet connection for static IP configuration

### Software Requirements
- Fresh Ubuntu 24.10 installation
- User with sudo privileges (script assumes username `jason`)
- Internet connection for package downloads

### Pre-Installation Setup
If using the autoinstall method:
1. Generate password hash: `mkpasswd --method=SHA-512`
2. Update `autoinstall.yaml` with your password hash
3. Host the setup scripts on a web server or modify the `runcmd` section

## 🚀 Installation Order

**⚠️ CRITICAL: Run scripts in this exact order to avoid dependency issues**

### For Fresh Desktop Installation:

```bash
# 1. System Configuration (MUST RUN FIRST)
sudo ./system_config.sh

# 2. Application Installation
sudo ./app_install.sh

# 3. Desktop Environment Configuration
sudo ./desktop_config.sh

# 4. GNOME Extensions (optional but recommended)
sudo ./gnome_extensions.sh
# OR for Just Perfection only:
sudo ./install_just_perfection.sh

# 5. Reboot to apply all changes
sudo reboot
```

### For Existing Installation with Separate Home Partition:

```bash
# Run this BEFORE the main installation scripts
./relink_home.sh
```

## 📝 Script Descriptions

### Core Installation Scripts

#### `system_config.sh` 🏗️
**Purpose**: Essential system-level configurations
- **Swap Verification**: Ensures 16-17GB swap partition exists on the OS drive
- **Network Configuration**: Sets static IP 192.168.1.69 with Cloudflare DNS
- **Wake-on-LAN**: Configures WoL for remote wake capability
- **SSH Server**: Enables and configures OpenSSH
- **Display Manager**: Forces X11 over Wayland for compatibility
- **Sudo Configuration**: Sets up passwordless sudo for the current user

#### `app_install.sh` 📦
**Purpose**: Installs development tools, applications, and services
- **Development Tools**: VS Code, Cursor, Docker, GitHub CLI, pyenv, nvm, Rust
- **Gaming**: Steam, ckb-next (Corsair keyboards), Piper (gaming mice)
- **Communication**: Discord, Signal, Spotify
- **Utilities**: 1Password, RustDesk, LocalSend, Flatseal
- **System Monitoring**: Custom disk monitor and Discord notifications
- **Virtualization**: QEMU/KVM with virt-manager

#### `desktop_config.sh` 🎨
**Purpose**: Configures GNOME desktop environment
- **Theme**: Sets dark theme system-wide
- **Dock Configuration**: Left-side dock with auto-hide
- **Application Pinning**: Configures favorite apps in dock
- **Terminal Setup**: Configures Kitty terminal with proper desktop integration

#### `gnome_extensions.sh` 🧩
**Purpose**: Installs and configures GNOME extensions
- **Tiling Shell**: Advanced window management
- **Unite**: Unified window decorations
- **Hide Top Bar**: Auto-hiding top panel

### Utility Scripts

#### `relink_home.sh` 🔗
**Purpose**: Reconnects existing home directory from separate partition
- **Use Case**: When reinstalling Ubuntu but keeping existing /home
- **Features**: UID matching, fstab configuration, backup creation
- **Safety**: Extensive validation and confirmation prompts

#### `install_just_perfection.sh` ⚡
**Purpose**: Installs Just Perfection GNOME extension
- **Alternative**: Lighter alternative to the full extension suite
- **Configuration**: Minimal panel and dash setup

#### `reset_gnome_extensions.sh` 🔄
**Purpose**: Emergency reset for problematic extensions
- **Use Case**: When extensions cause desktop instability
- **Function**: Disables all extensions and resets configurations

#### `autoinstall.yaml` 🤖
**Purpose**: Unattended Ubuntu installation configuration
- **Disk Layout**: 500MB boot, 30GB root, 16GB swap
- **User Setup**: Creates user `jason` with hashed password
- **Post-Install**: Downloads and runs setup scripts automatically

## ⚠️ Dangerous Operations & Warnings

### Critical System Changes
1. **Network Configuration**: 
   - Sets static IP 192.168.1.69
   - **Risk**: May lose network connectivity if gateway isn't 192.168.1.1
   - **Mitigation**: Verify network settings before running

2. **Swap Partition Requirements**:
   - **Risk**: Script will exit if proper swap isn't found
   - **Requirement**: 16-17GB swap partition on same disk as root
   - **Verification**: Check with `swapon --show` before running

3. **Sudo Configuration**:
   - Enables passwordless sudo for current user
   - **Risk**: Reduces security if system is compromised
   - **Mitigation**: Only use on trusted systems

4. **Display Manager Changes**:
   - Forces X11 over Wayland
   - **Risk**: May cause display issues on some systems
   - **Recovery**: Edit `/etc/gdm3/custom.conf` to re-enable Wayland

### Data Safety
- **Home Directory**: `relink_home.sh` moves `/home` to `/home.bak`
- **Backups**: Always creates backups before major changes
- **Validation**: Extensive checks before destructive operations

## ✅ Safe Configuration Options

### Testing Mode
```bash
# Dry-run to see what would be installed (apps only)
apt list --upgradable | grep -E "package-name"
```

### Partial Installation
Run individual components:
```bash
# System only (safest)
sudo ./system_config.sh

# Apps only (requires system config first)
sudo ./app_install.sh

# Desktop only
sudo ./desktop_config.sh
```

### Rollback Options
- **Networking**: Restore `/etc/netplan/01-netcfg.yaml.backup`
- **fstab**: Restore from `/etc/fstab.backup.TIMESTAMP`
- **Extensions**: Run `./reset_gnome_extensions.sh`

## 🖥️ Headless Server Installation

For server/SSH-only installations, use the scripts in the `headless/` directory. These provide the same functionality without GUI components.

See [`headless/README.md`](headless/README.md) for specific instructions.

## 🔧 Troubleshooting

### Common Issues

#### Network Connectivity Lost
```bash
# Restore original netplan
sudo cp /etc/netplan/01-netcfg.yaml.backup /etc/netplan/01-netcfg.yaml
sudo netplan apply
```

#### GNOME Extensions Broken Desktop
```bash
# Reset all extensions
./reset_gnome_extensions.sh
# Or manually:
gsettings set org.gnome.shell disable-user-extensions true
```

#### Swap Not Detected
```bash
# Check current swap
swapon --show
# Check partition table
sudo fdisk -l
# Ensure swap is in fstab
grep swap /etc/fstab
```

#### Permission Issues After UID Change
```bash
# Find and fix ownership
sudo find /home/username -user OLD_UID -exec chown NEW_UID:NEW_GID {} \;
```

### Logs and Debugging
- Application install logs: Check terminal output during `app_install.sh`
- Extension logs: `~/.local/share/gnome-extensions-setup.log`
- System logs: `journalctl -u service-name`

## 🤝 Contributing

This is a personal automation project, but improvements are welcome:
1. Test on different hardware configurations
2. Add support for other Ubuntu versions
3. Improve error handling and recovery
4. Add more application options

## 📄 License

MIT License - Feel free to adapt for your own needs.

---

**⚠️ Final Warning**: These scripts make significant system changes. Always test on a virtual machine first and ensure you have backups of important data before running on production systems.

