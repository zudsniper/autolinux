#!/bin/bash
set -e
echo "Installing headless applications..."

# Helper functions
is_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
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

# Basic packages for headless systems
apt update && apt upgrade -y
BASIC_PACKAGES="curl jq git fail2ban net-tools vim build-essential python3 python-is-python3 htop tmux openssh-server ca-certificates software-properties-common apt-transport-https gnupg lsb-release wget ethtool xclip p7zip-full btop nvtop unzip tree ncdu"
for pkg in $BASIC_PACKAGES; do
    if ! is_package_installed "$pkg"; then
        echo "Installing $pkg..."
        apt install -y "$pkg"
    else
        echo "$pkg already installed, skipping."
    fi
done

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

# UFW Firewall
if ! is_package_installed "ufw"; then
    echo "Installing UFW..."
    apt install -y ufw
    
    # Basic firewall configuration for headless systems
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 9443/tcp  # Portainer HTTPS
    ufw --force enable
else
    echo "UFW already installed, skipping."
fi

# OpenVPN client
OPENVPN_PACKAGES="openvpn"
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

# Additional CLI tools for server management
CLI_TOOLS="screen ripgrep fd-find exa bat micro tig lazygit"
for pkg in $CLI_TOOLS; do
    if ! is_package_installed "$pkg"; then
        echo "Installing $pkg..."
        apt install -y "$pkg" 2>/dev/null || echo "Warning: Could not install $pkg"
    else
        echo "$pkg already installed, skipping."
    fi
done

# Discord startup notification (headless version using curl)
if [ ! -f /usr/local/bin/discord.sh ]; then
    echo "Setting up Discord notification scripts (headless)..."
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

# Additional server security hardening
echo "Configuring additional security..."

# Secure shared memory
if ! grep -q "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" /etc/fstab; then
    echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
fi

# Configure fail2ban for SSH
if [ -f /etc/fail2ban/jail.conf ] && [ ! -f /etc/fail2ban/jail.local ]; then
    echo "Configuring fail2ban..."
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
fi

# Install useful aliases for headless management
if [ ! -f /home/jason/.bash_aliases ]; then
    echo "Setting up useful aliases..."
    cat > /home/jason/.bash_aliases << EOF
# System monitoring
alias ports='netstat -tulanp'
alias meminfo='free -m -l -t'
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias pscpu='ps auxf | sort -nr -k 3'
alias pscpu10='ps auxf | sort -nr -k 3 | head -10'
alias cpuinfo='lscpu'
alias gpumeminfo='grep -i --color memory /var/log/Xorg.0.log'

# Docker shortcuts
alias dps='docker ps'
alias dpa='docker ps -a'
alias di='docker images'
alias dlog='docker logs'
alias dexec='docker exec -it'

# System updates
alias update='sudo apt update && sudo apt upgrade'
alias install='sudo apt install'

# Directory shortcuts
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'
EOF
    chown jason:jason /home/jason/.bash_aliases
fi

echo "Headless application installation completed"
echo ""
echo "Summary of installed components:"
echo "- Development tools: git, vim, pyenv, nvm, Rust, Docker"
echo "- System monitoring: htop, btop, nvtop, custom disk monitor"
echo "- Security: fail2ban, UFW firewall"
echo "- Remote access: SSH, OpenVPN"
echo "- Container management: Docker, Portainer"
echo "- CLI utilities: ripgrep, fd-find, exa, bat, and more"
echo ""
echo "Access Portainer at: https://your-server-ip:9443"
echo "Default firewall rules applied - SSH and Portainer ports are open" 