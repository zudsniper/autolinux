# Headless Ubuntu 24.10 Configuration Scripts

Headless/server versions of the main Ubuntu 24.10 configuration scripts, designed for SSH-only environments without GUI components.

## 🖥️ Purpose

These scripts provide the same core functionality as the main installation scripts but exclude all GUI-related components:
- No GNOME/desktop environment configurations
- No GUI applications (browsers, Steam, Discord, etc.)
- No X11/Wayland display manager changes
- Focus on CLI tools, development environments, and server functionality

## 📦 What's Included

### `system_config_headless.sh`
- Swap partition verification and configuration
- Network configuration (static IP 192.168.1.69)
- Wake-on-LAN setup
- SSH server configuration
- Sudo configuration (passwordless)
- **Excluded**: X11/GNOME display manager configs

### `app_install_headless.sh`
- Development tools: Docker, GitHub CLI, pyenv, nvm, Rust
- CLI utilities: vim, tmux, htop, btop, nvtop
- System tools: fail2ban, UFW firewall
- Remote access: OpenVPN, SSH tools
- **Excluded**: All GUI applications (browsers, games, desktop apps)

### `relink_home.sh`
- **Unchanged**: Works identically for both GUI and headless systems
- Use this to reconnect existing home directories from separate partitions

## 🚀 Installation Order

```bash
# 1. System Configuration (MUST RUN FIRST)
sudo ./system_config_headless.sh

# 2. Application Installation
sudo ./app_install_headless.sh

# 3. Optional: Relink existing home directory
./relink_home.sh

# 4. Reboot to apply all changes
sudo reboot
```

## 🔧 Key Differences from GUI Version

### Removed Components
- **GUI Applications**: Steam, Discord, Spotify, browsers, etc.
- **Desktop Environment**: No GNOME configurations or extensions
- **Display Manager**: No X11/Wayland modifications
- **Flatpak GUI Apps**: Only CLI tools remain

### Server-Optimized Features
- Focused on headless operation
- Reduced resource usage
- Enhanced security (fail2ban, UFW)
- Remote administration tools
- Development environment setup

## 📋 Prerequisites

- Fresh Ubuntu 24.10 Server installation
- User with sudo privileges
- Internet connection
- SSH access configured

## ⚠️ Same Warnings Apply

- **Network Configuration**: Still sets static IP 192.168.1.69
- **Swap Requirements**: Still requires 16-17GB swap partition
- **System Changes**: Makes significant system modifications

See the main [README.md](../README.md) for detailed warnings and troubleshooting.

## 🔄 Converting Existing Desktop Installation

If you have an existing desktop installation and want to remove GUI components:

```bash
# Remove desktop packages (be very careful!)
sudo apt autoremove ubuntu-desktop-minimal ubuntu-desktop
sudo apt autoremove gnome-shell gnome-session

# Reconfigure for console-only boot
sudo systemctl set-default multi-user.target
```

**Warning**: This will remove the desktop environment entirely. Make sure you have SSH access before proceeding.

## 📝 Customization

To customize these scripts for your environment:

1. **Network Settings**: Edit the static IP configuration in `system_config_headless.sh`
2. **Applications**: Modify the package lists in `app_install_headless.sh`
3. **User Configuration**: Change the hardcoded username references if needed

## 🔗 Usage with Cloud/VPS Providers

These scripts work well with:
- AWS EC2 instances
- Digital Ocean Droplets
- Google Cloud Compute Engine
- Local VMs and bare metal servers

Just ensure the provider allows:
- Custom kernel parameters (for swap)
- Network interface configuration
- Package installation from repositories 