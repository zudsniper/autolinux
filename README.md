# Ubuntu Auto-Configuration Scripts

A complete automation suite for setting up Ubuntu (24.10 / 25.10) with a custom desktop environment, applications, and system configurations. Includes a safe Xubuntu→GNOME migration flow that survives reboots.

## Recommended: `bootstrap.sh`

> **⚠️ UNTESTED ON REAL HARDWARE — 2026-05-06.** The state machine, stage logic, and lib/ helpers have only been exercised via `--dry-run` on a machine that is already on GNOME (cleanup-only path) and via the `tests/state-machine.sh` unit suite. The full Xubuntu→GNOME migration flow (stages 04–07: install GNOME stack, switch DM, reboot, verify) has **not been validated on a live Xubuntu install**. Test in a VM before running on a machine you care about. Use `--dry-run` first.

`bootstrap.sh` is a state-machine orchestrator that runs the migration and setup as 16 ordered stages with checkpoints in `/var/lib/autolinux/state.json`. Stages that need a reboot exit cleanly after arming a resume hook (autostart `.desktop` + systemd unit) so the next login picks up exactly where it left off.

```bash
sudo ./bootstrap.sh                  # auto-detect + run pending stages
sudo ./bootstrap.sh --status         # show state machine + per-stage status
sudo ./bootstrap.sh --dry-run        # show what would happen, change nothing
sudo ./bootstrap.sh --list-stages    # print the stage list
sudo ./bootstrap.sh --rollback       # release holds, remove resume hooks, list snapshots
sudo ./bootstrap.sh --only 08-remove-xfce        # run one stage
sudo ./bootstrap.sh --from 10-system-config      # start at a stage; earlier stages must already be done
sudo ./bootstrap.sh --force-replay 03-detect-starting-de   # re-run a 'done' stage
sudo ./bootstrap.sh --yes            # accept all confirmation prompts
sudo ./bootstrap.sh --allow-pending-upgrades     # bypass the 'no pending upgrades' guard
```

### What the stages do

| # | Stage | Reboots? |
|---|---|---|
| 00 | preflight (Ubuntu? dpkg sane? no pending upgrades? network?) | no |
| 01 | timeshift snapshot tagged `autolinux-pre-migration` | no |
| 02 | `apt-mark hold` for ubuntu-desktop, gdm3, gnome-shell, kernel, GRUB, shim | no |
| 02a | GPU driver check — detect vendor + bound kernel module, recommend/install vendor driver (NVIDIA proprietary on Ampere/Lovelace, mesa/vulkan on AMD/Intel) | only if NVIDIA installed |
| 03 | record starting DE / DM / session type in state.json | no |
| 04 | install GNOME stack (`ubuntu-desktop gdm3 gnome-shell gnome-session ...`) | no |
| 05 | switch default display manager to gdm3 (debconf-preseeded) | no |
| 06 | arm resume hook + reboot, **only if** the running DE is not GNOME | **yes** |
| 07 | post-reboot: confirm GNOME session is active and GDM3 is default | no |
| 08 | safely purge xfce4-/xubuntu-/libxfce4*/lightdm packages (computed live, ubuntu-desktop deps excluded) | no |
| 09 | archive `~/.config/xfce4/` to `~/.config/autolinux-backup/xfce4-<ts>/` | no |
| 10 | run `system_config.sh` (swap, network, SSH, X11, NOPASSWD sudo) | no |
| 11 | run `app_install.sh` (Chrome, 1Password, Discord, Steam, Rust, ringboard, …) | no |
| 12 | run `desktop_config.sh` (GNOME theme, dock, favorite apps) | no |
| 13 | run `gnome_extensions.sh` (Tiling Shell, Hide Top Bar) | no |
| 14 | release the package holds added in stage 02 | no |
| 15 | remove resume hooks, optional snapshot deletion, summary | no |

Stages individually detect "already satisfied" by inspecting the live system, **independent of state.json**. So if you run bootstrap on a box where someone manually installed GNOME, it will skip stages 02–07 and pick up at the cleanup steps. State drift (a "done" stage that no longer detects) aborts with a `--force-replay` hint instead of silently re-running.

### Safety mechanisms

- **Never purge XFCE while inside an XFCE session.** Stage 08 hard-aborts.
- **Hold before purge.** ubuntu-desktop, gdm3, gnome-shell, linux-generic, GRUB, shim are all held during stages 02–13 so `apt autoremove` cannot cascade them out.
- **Computed purge set, not a static kill list.** Stage 08 subtracts deps of ubuntu-desktop / ubuntu-desktop-minimal / gnome-shell from the xfce-pattern match.
- **Bootloader integrity check before every reboot.** Two kernels in `/boot`, ≥200MB free on `/boot/efi`, valid efibootmgr entry.
- **Pre-migration timeshift snapshot.** rsync mode (works on ext4). Tagged so we can find/remove ours.
- **Atomic state writes** with `mv tmp final` and a JSON-validation gate before publish.
- **`--dry-run`** prints every `apt`/`mv`/`dpkg` invocation without touching the system.
- **GPU driver auto-recommendation** (stage 02a). If an NVIDIA Maxwell+ card is bound to `nouveau`, bootstrap prompts to install the `ubuntu-drivers`-recommended `nvidia-driver-*` package (with apt simulation preview) and queues a reboot. AMD/Intel cards get their userspace mesa/vulkan/VA bits checked. Pre-Maxwell NVIDIA cards on `nouveau` are left alone.

### Resume across reboot

Stage 06 installs two layers of resume hook before rebooting:
1. `~/.config/autostart/autolinux-resume.desktop` (primary; matches the existing repo's autostart pattern)
2. `/etc/systemd/system/autolinux-resume.service` (fallback if user disabled autostart globally)

Both invoke `/usr/local/bin/autolinux-resume`, which opens a terminal (kitty / gnome-terminal / xterm in that order) and runs `sudo -E ./bootstrap.sh --resume`. The wrapper self-removes when state.status is `done`. Stage 15 also removes the hooks explicitly.

### Tests

```bash
./tests/state-machine.sh
```

Exercises state.sh atomic writes, malformed-JSON recovery, stage transitions, array dedupe/replace, detect.sh helpers, and bootstrap.sh CLI flags.

---

## Project Overview

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

## 🚀 Installation Order (Advanced / Manual Mode)

**⚠️ Most users should use `sudo ./bootstrap.sh` instead — see the top of this README.**

The instructions below are for running individual scripts directly, without the state-machine wrapper. There is no resume-across-reboot, no preflight check, and no timeshift snapshot — you are responsible for those yourself.

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

