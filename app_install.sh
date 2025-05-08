#!/bin/bash
set -e
echo "Installing applications..."

# Helper functions
is_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

is_flatpak_installed() {
    flatpak list 2>/dev/null | grep -q "$1"
}

is_container_running() {
    docker ps -a 2>/dev/null | grep -q "$1"
}

is_repository_added() {
    grep -q "$1" /etc/apt/sources.list.d/*.list 2>/dev/null
}

is_service_enabled() {
    systemctl is-enabled "$1" &>/dev/null
}

# Basic packages
apt update && apt upgrade -y
BASIC_PACKAGES="curl jq git fail2ban net-tools vim build-essential python3 python-is-python3 htop tmux openssh-server ca-certificates software-properties-common apt-transport-https gnupg lsb-release wget ethtool xclip"
for pkg in $BASIC_PACKAGES; do
    if ! is_package_installed "$pkg"; then
        echo "Installing $pkg..."
        apt install -y "$pkg"
    else
        echo "$pkg already installed, skipping."
    fi
done

# Flatpak
if ! is_package_installed "flatpak"; then
    echo "Installing flatpak..."
    apt install -y flatpak
fi

if ! flatpak remotes | grep -q "flathub"; then
    echo "Adding flathub repository..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Flatseal
if ! is_flatpak_installed "com.github.tchx84.Flatseal"; then
    echo "Installing Flatseal..."
    flatpak install -y flathub com.github.tchx84.Flatseal
else
    echo "Flatseal already installed, skipping."
fi

# Steam (via flatpak)
if ! is_flatpak_installed "com.valvesoftware.Steam"; then
    echo "Installing Steam..."
    flatpak install -y flathub com.valvesoftware.Steam
else
    echo "Steam already installed, skipping."
fi

# Google Chrome
if ! is_package_installed "google-chrome-stable"; then
    echo "Installing Google Chrome..."
    if [ ! -f google-chrome-stable_current_amd64.deb ]; then
        wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    fi
    apt install -y ./google-chrome-stable_current_amd64.deb
    rm -f google-chrome-stable_current_amd64.deb
else
    echo "Google Chrome already installed, skipping."
fi

# 1Password
if ! is_package_installed "1password"; then
    echo "Installing 1Password..."
    if [ ! -f /usr/share/keyrings/1password-archive-keyring.gpg ]; then
        curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    fi
    if ! is_repository_added "downloads.1password.com"; then
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | tee /etc/apt/sources.list.d/1password.list
        apt update
    fi
    apt install -y 1password 1password-cli
else
    echo "1Password already installed, skipping."
fi

# RustDesk
if ! is_flatpak_installed "com.rustdesk.RustDesk"; then
    echo "Installing RustDesk..."
    flatpak install -y flathub com.rustdesk.RustDesk
else
    echo "RustDesk already installed, skipping."
fi

# Discord
if ! is_flatpak_installed "com.discordapp.Discord"; then
    echo "Installing Discord..."
    flatpak install -y flathub com.discordapp.Discord
else
    echo "Discord already installed, skipping."
fi

# Discord startup notification
if [ ! -f /usr/local/bin/discord.sh ]; then
    echo "Setting up Discord notification scripts..."
    curl -o /usr/local/bin/discord.sh https://raw.githubusercontent.com/fieu/discord.sh/master/discord.sh
    chmod +x /usr/local/bin/discord.sh
    curl -o /usr/local/bin/startup_notification.sh https://gist.githubusercontent.com/zudsniper/cac1d22e06d57bcb2b1208ed3ce5400e/raw/startup_notification.sh
    chmod +x /usr/local/bin/startup_notification.sh
fi

# Discord startup service
if [ ! -f /etc/systemd/system/discord-startup.service ]; then
    echo "Setting up Discord startup service..."
    cat > /etc/systemd/system/discord-startup.service << EOF
[Unit]
Description=Discord Startup Notification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/startup_notification.sh
User=jason

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable discord-startup.service
fi

# Disk monitor
if [ ! -f /usr/local/bin/disk_monitor.py ]; then
    echo "Setting up disk monitor..."
    curl -o /usr/local/bin/disk_monitor.py https://gist.githubusercontent.com/zudsniper/2283b66f964b134e7a75c7ad0a045dc5/raw/disk_monitor.py
    chmod +x /usr/local/bin/disk_monitor.py
fi

# Disk monitor service
if [ ! -f /etc/systemd/system/disk-monitor.service ]; then
    echo "Setting up disk monitor service..."
    cat > /etc/systemd/system/disk-monitor.service << EOF
[Unit]
Description=Disk Usage Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/disk_monitor.py
User=jason
Restart=always
RestartSec=3600

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable disk-monitor.service
fi

# Spotify
if ! is_flatpak_installed "com.spotify.Client"; then
    echo "Installing Spotify..."
    flatpak install -y flathub com.spotify.Client
else
    echo "Spotify already installed, skipping."
fi

# QEMU & virt-manager
QEMU_PACKAGES="qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager"
QEMU_NEEDED=0
for pkg in $QEMU_PACKAGES; do
    if ! is_package_installed "$pkg"; then
        QEMU_NEEDED=1
        break
    fi
done

if [ $QEMU_NEEDED -eq 1 ]; then
    echo "Installing QEMU and virt-manager..."
    apt install -y $QEMU_PACKAGES
else
    echo "QEMU and virt-manager already installed, skipping."
fi

# pyenv
PYENV_DEPENDENCIES="make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python3-openssl"
PYENV_DEPS_NEEDED=0
for pkg in $PYENV_DEPENDENCIES; do
    if ! is_package_installed "$pkg"; then
        PYENV_DEPS_NEEDED=1
        break
    fi
done

if [ $PYENV_DEPS_NEEDED -eq 1 ]; then
    echo "Installing pyenv dependencies..."
    apt install -y $PYENV_DEPENDENCIES
fi

if [ ! -d "/root/.pyenv" ] && [ ! -d "/home/jason/.pyenv" ]; then
    echo "Installing pyenv..."
    curl https://pyenv.run | bash
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
else
    echo "pyenv already installed, skipping."
fi

# nvm
if [ ! -d "/root/.nvm" ] && [ ! -d "/home/jason/.nvm" ]; then
    echo "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
else
    echo "nvm already installed, skipping."
fi

# GitHub CLI
if ! is_package_installed "gh"; then
    echo "Installing GitHub CLI..."
    if [ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    fi
    if ! is_repository_added "cli.github.com"; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        apt update
    fi
    apt install -y gh
else
    echo "GitHub CLI already installed, skipping."
fi

# VS Code
if ! is_package_installed "code"; then
    echo "Installing VS Code..."
    if [ ! -f /usr/share/keyrings/vscode.gpg ]; then
        wget -O- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /usr/share/keyrings/vscode.gpg > /dev/null
    fi
    if ! is_repository_added "packages.microsoft.com/repos/vscode"; then
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vscode.list > /dev/null
        apt update
    fi
    apt install -y code
else
    echo "VS Code already installed, skipping."
fi

# Cursor
if ! command -v cursor &> /dev/null; then
    echo "Installing Cursor..."
    curl -fsSL https://gist.githubusercontent.com/tatosjb/0ca8551406499d52d449936964e9c1d6/raw/5d6ad7ede60611dafa30ad29a4b8caabb671db5b/install-cursor-sh | bash
else
    echo "Cursor already installed, skipping."
fi

# Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    fi
    if ! is_repository_added "download.docker.com"; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
    fi
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker $USER
else
    echo "Docker already installed, skipping."
fi

# Portainer
if ! is_container_running "portainer"; then
    echo "Installing Portainer..."
    docker volume create portainer_data
    docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
else
    echo "Portainer already running, skipping."
fi

# UFW
if ! is_package_installed "ufw"; then
    echo "Installing UFW..."
    apt install -y ufw
else
    echo "UFW already installed, skipping."
fi

# LocalSend
if ! is_flatpak_installed "org.localsend.localsend_app"; then
    echo "Installing LocalSend..."
    flatpak install -y flathub org.localsend.localsend_app
else
    echo "LocalSend already installed, skipping."
fi

# Signal Messenger
if ! is_package_installed "signal-desktop"; then
    echo "Installing Signal..."
    if [ ! -f /usr/share/keyrings/signal-desktop-keyring.gpg ]; then
        wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /usr/share/keyrings/signal-desktop-keyring.gpg
    fi
    if ! is_repository_added "updates.signal.org"; then
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" | tee /etc/apt/sources.list.d/signal-xenial.list > /dev/null
        apt update
    fi
    apt install -y signal-desktop
else
    echo "Signal already installed, skipping."
fi

# Kleopatra
if ! is_package_installed "kleopatra"; then
    echo "Installing Kleopatra..."
    apt install -y kleopatra
else
    echo "Kleopatra already installed, skipping."
fi

# OpenVPN
OPENVPN_PACKAGES="openvpn network-manager-openvpn network-manager-openvpn-gnome"
OPENVPN_NEEDED=0
for pkg in $OPENVPN_PACKAGES; do
    if ! is_package_installed "$pkg"; then
        OPENVPN_NEEDED=1
        break
    fi
done

if [ $OPENVPN_NEEDED -eq 1 ]; then
    echo "Installing OpenVPN..."
    apt install -y $OPENVPN_PACKAGES
else
    echo "OpenVPN already installed, skipping."
fi

# ckb-next for Corsair keyboard
if ! is_package_installed "ckb-next"; then
    echo "Installing ckb-next..."
    if ! grep -q "ppa:tatokis/ckb-next" /etc/apt/sources.list.d/*.list; then
        add-apt-repository -y ppa:tatokis/ckb-next
        apt update
    fi
    apt install -y ckb-next
else
    echo "ckb-next already installed, skipping."
fi

# Piper for gaming mouse (alternative to G HUB)
PIPER_PACKAGES="piper ratbagd"
PIPER_NEEDED=0
for pkg in $PIPER_PACKAGES; do
    if ! is_package_installed "$pkg"; then
        PIPER_NEEDED=1
        break
    fi
done

if [ $PIPER_NEEDED -eq 1 ]; then
    echo "Installing Piper..."
    apt install -y $PIPER_PACKAGES
    systemctl enable ratbagd
    systemctl start ratbagd
else
    echo "Piper already installed, skipping."
    if ! systemctl is-active --quiet ratbagd; then
        systemctl start ratbagd
    fi
fi

# Properly install Rust with environment sourcing
check_rust_installed() {
    # Check if rustc is in path
    if command -v rustc &> /dev/null; then
        return 0
    fi
    
    # Check if installation exists but not in path
    if [ -f "$HOME/.cargo/bin/rustc" ] || [ -f "/home/jason/.cargo/bin/rustc" ]; then
        source "$HOME/.cargo/env" 2>/dev/null || true
        return 0
    fi
    
    return 1
}

if ! check_rust_installed; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env" || true
    rustup toolchain install nightly
    rustup default stable
else
    echo "Rust already installed, skipping."
    # Ensure environment is sourced
    source "$HOME/.cargo/env" 2>/dev/null || true
    
    # Check if nightly toolchain is installed
    if ! rustup toolchain list | grep -q "nightly"; then
        echo "Installing Rust nightly toolchain..."
        rustup toolchain install nightly
    fi
fi

# Ringboard - fixed dependency approach
RINGBOARD_DEPS="build-essential libx11-dev libxfixes-dev libxtst-dev libfontconfig1-dev libglew-dev libgl1-mesa-dev libglu1-mesa-dev cmake"
RINGBOARD_DEPS_NEEDED=0
for pkg in $RINGBOARD_DEPS; do
    if ! is_package_installed "$pkg"; then
        RINGBOARD_DEPS_NEEDED=1
        break
    fi
done

if [ $RINGBOARD_DEPS_NEEDED -eq 1 ]; then
    echo "Installing Ringboard dependencies..."
    apt install -y $RINGBOARD_DEPS
fi

if ! command -v ringboard-server &> /dev/null; then
    echo "Installing Ringboard..."
    
    # Make sure Rust environment is sourced (it should be from earlier step)
    source "$HOME/.cargo/env" 2>/dev/null || true
    
    # Install server component
    cargo install clipboard-history-server --no-default-features --features systemd
    
    # Determine if Wayland or X11 and install appropriate component
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        echo "Detected Wayland session, installing Wayland component..."
        cargo install clipboard-history-wayland --no-default-features
    else
        echo "Detected X11 session (or couldn't determine), installing X11 component..."
        cargo install clipboard-history-x11 --no-default-features
    fi
    
    # Install egui frontend
    cargo install clipboard-history-egui --no-default-features --features wayland,x11
    
    # Set up proper egui keyboard shortcut command
    EGUI_COMMAND=$(bash -c 'echo /bin/sh -c \"ps -p \`cat /tmp/.ringboard/$USERNAME.egui-sleep 2\> /dev/null\` \> /dev/null 2\>\&1 \&\& exec rm -f /tmp/.ringboard/$USERNAME.egui-sleep \|\| exec $(which ringboard-egui)\"')
    
    # Create desktop entry for keyboard shortcut
    mkdir -p /usr/share/applications
    cat > /usr/share/applications/ringboard-egui.desktop << EOF
[Desktop Entry]
Name=Ringboard Clipboard
Comment=Ringboard egui clipboard manager
Exec=${EGUI_COMMAND}
Type=Application
Terminal=false
Categories=Utility;
EOF

    # Set up keyboard shortcut for GNOME
    if command -v gsettings &> /dev/null; then
        # Add custom keybinding for user jason
        sudo -u jason dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/name "'Ringboard Clipboard'"
        sudo -u jason dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/command "'${EGUI_COMMAND}'"
        sudo -u jason dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/binding "'<Control><Super><Alt>c'"
        
        # Update custom keybindings list
        CURRENT_BINDINGS=$(sudo -u jason dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings)
        if [ -z "$CURRENT_BINDINGS" ] || [ "$CURRENT_BINDINGS" == "@as []" ]; then
            sudo -u jason dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/']"
        elif [[ ! $CURRENT_BINDINGS == *"ringboard"* ]]; then
            # Remove brackets and closing bracket
            CURRENT_BINDINGS=${CURRENT_BINDINGS:0:-1}
            # Append new binding
            if [[ $CURRENT_BINDINGS == *"]"* ]]; then
                # Add comma if the list is not empty
                CURRENT_BINDINGS="${CURRENT_BINDINGS}, '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/']"
            else
                # Handle case for empty list
                CURRENT_BINDINGS="${CURRENT_BINDINGS}'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ringboard/']"
            fi
            sudo -u jason dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "$CURRENT_BINDINGS"
        fi
    fi
    
    # Create systemd user services directory for user
    sudo -u jason mkdir -p /home/jason/.config/systemd/user/
    
    # Enable services for user jason
    sudo -u jason systemctl --user enable ringboard-server
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        sudo -u jason systemctl --user enable ringboard-wayland
    else
        sudo -u jason systemctl --user enable ringboard-x11
    fi
    
    # Start services
    sudo -u jason systemctl --user start ringboard-server
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        sudo -u jason systemctl --user start ringboard-wayland
    else
        sudo -u jason systemctl --user start ringboard-x11
    fi
else
    echo "Ringboard already installed, skipping."
fi

# VLC
if ! is_package_installed "vlc"; then
    echo "Installing VLC..."
    apt install -y vlc
else
    echo "VLC already installed, skipping."
fi

# Transmission
if ! is_package_installed "transmission-gtk"; then
    echo "Installing Transmission..."
    apt install -y transmission-gtk
else
    echo "Transmission already installed, skipping."
fi

# Kitty terminal
if [ ! -f /usr/local/bin/kitty ]; then
    echo "Installing Kitty terminal..."
    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
    ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten /usr/local/bin/
    mkdir -p ~/.local/share/applications
    cp ~/.local/kitty.app/share/applications/kitty.desktop ~/.local/share/applications/
    cp ~/.local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
else
    echo "Kitty terminal already installed, skipping."
fi

# Claude Desktop
if ! is_package_installed "claude-desktop"; then
    echo "Installing Claude Desktop..."
    
    NODE_PACKAGES="npm nodejs"
    NODE_NEEDED=0
    for pkg in $NODE_PACKAGES; do
        if ! is_package_installed "$pkg"; then
            NODE_NEEDED=1
            break
        fi
    done
    
    if [ $NODE_NEEDED -eq 1 ]; then
        apt install -y $NODE_PACKAGES
    fi
    
    CLAUDE_DEPS="libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libuuid1 libsecret-1-0"
    CLAUDE_DEPS_NEEDED=0
    for pkg in $CLAUDE_DEPS; do
        if ! is_package_installed "$pkg"; then
            CLAUDE_DEPS_NEEDED=1
            break
        fi
    done
    
    if [ $CLAUDE_DEPS_NEEDED -eq 1 ]; then
        apt install -y $CLAUDE_DEPS
    fi
    
    # Clone and build Claude Desktop
    cd /tmp
    if [ -d claude-desktop-debian ]; then
        rm -rf claude-desktop-debian
    fi
    git clone https://github.com/aaddrick/claude-desktop-debian.git
    cd claude-desktop-debian
    ./build.sh --build deb --clean yes
    apt install -y ./claude-desktop_*.deb
    cd /tmp
    rm -rf claude-desktop-debian
else
    echo "Claude Desktop already installed, skipping."
fi

echo "Application installation completed"