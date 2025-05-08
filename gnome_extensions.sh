#!/bin/bash
# Installs and configures GNOME extensions

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
  echo -e "\n${BOLD}${PURPLE}$1${NC}\n"
}

log_header "Installing GNOME extensions..."

# Determine the correct user
if [ "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

log_info "Installing extensions for user: ${CYAN}$REAL_USER${NC}"

# Install required dependencies
log_info "Installing required dependencies..."
apt update
apt install -y gnome-shell-extensions gnome-shell-extension-manager gnome-tweaks \
  git x11-utils gettext libglib2.0-dev unzip wget

# Check for npm, install if not found
if ! command -v npm &> /dev/null; then
  log_info "Installing npm..."
  apt install -y npm nodejs
fi

# Create temporary directory for installations
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
chown -R "$REAL_USER:$REAL_USER" "$TEMP_DIR"

# Get D-Bus session address (this is needed for GNOME related commands)
if [ "$SUDO_USER" ]; then
  DBUS_SESSION_BUS_ADDRESS=$(su - "$REAL_USER" -c 'echo $DBUS_SESSION_BUS_ADDRESS')
  [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $REAL_USER)/bus"
  export DBUS_SESSION_BUS_ADDRESS
fi

# Function to handle errors
handle_error() {
  log_error "$1"
  log_info "Cleaning up..."
  rm -rf "$TEMP_DIR"
  exit 1
}

# Check if GNOME extensions are enabled system-wide
check_extensions_enabled() {
  if su - "$REAL_USER" -c "gsettings get org.gnome.shell disable-user-extensions" | grep -q "true"; then
    log_warning "GNOME extensions are disabled system-wide!"
    log_warning "Extensions will be installed but not active until you enable them."
    log_warning "To enable extensions, run: gsettings set org.gnome.shell disable-user-extensions false"
    log_warning "Waiting 7 seconds before continuing..."
    sleep 7
    
    # Offer to enable extensions automatically
    read -p "$(echo -e "${YELLOW}Would you like to enable extensions now? (y/n)${NC} ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      su - "$REAL_USER" -c "gsettings set org.gnome.shell disable-user-extensions false"
      log_success "Extensions enabled system-wide."
    else
      log_warning "Extensions will remain disabled. You can enable them manually later."
    fi
  else
    log_success "GNOME extensions are already enabled system-wide."
  fi
}

# Function to check if extension is already installed
is_extension_installed() {
  local uuid=$1
  su - "$REAL_USER" -c "gnome-extensions list | grep -q \"$uuid\"" && return 0 || return 1
}

# Check if extensions are enabled
check_extensions_enabled

# Install gTile
if is_extension_installed "gTile@vibou"; then
  log_success "gTile is already installed, skipping..."
else
  log_header "Installing gTile from source..."
  su - "$REAL_USER" -c "cd $TEMP_DIR && \
    git clone https://github.com/gTile/gTile.git && \
    cd gTile && \
    npm ci && \
    npm run build:dist && \
    npm run install:extension" || handle_error "Failed to install gTile"
  log_success "gTile installed successfully."
fi

# Install Unite
if is_extension_installed "unite@hardpixel.eu"; then
  log_success "Unite is already installed, skipping..."
else
  log_header "Installing Unite..."
  UNITE_VERSION="v82"
  su - "$REAL_USER" -c "cd $TEMP_DIR && \
    wget https://github.com/hardpixel/unite-shell/releases/download/${UNITE_VERSION}/unite-${UNITE_VERSION}.zip -O unite.zip && \
    gnome-extensions install --force unite.zip" || handle_error "Failed to install Unite"
  log_success "Unite installed successfully."
fi

# Install Hide Top Bar
if is_extension_installed "hidetopbar@mathieu.bidon.ca"; then
  log_success "Hide Top Bar is already installed, skipping..."
else
  log_header "Installing Hide Top Bar from source..."
  su - "$REAL_USER" -c "cd $TEMP_DIR && \
    git clone https://gitlab.gnome.org/tuxor1337/hidetopbar.git && \
    cd hidetopbar && \
    make && \
    gnome-extensions install ./hidetopbar.zip" || handle_error "Failed to install Hide Top Bar from source"
  log_success "Hide Top Bar installed successfully."
fi

# Install Just Perfection
if is_extension_installed "just-perfection-desktop@just-perfection"; then
  log_success "Just Perfection is already installed, skipping..."
else
  log_header "Installing Just Perfection..."
  su - "$REAL_USER" -c "cd $TEMP_DIR && \
    git clone https://gitlab.gnome.org/jrahmatzadeh/just-perfection.git && \
    cd just-perfection && \
    ./scripts/build.sh -i" || handle_error "Failed to install Just Perfection"
  log_success "Just Perfection installed successfully."
fi

# Clean up
rm -rf "$TEMP_DIR"

# Create script directory if it doesn't exist
log_info "Setting up autostart configuration..."
SCRIPT_DIR="/home/$REAL_USER/.local/bin"
mkdir -p "$SCRIPT_DIR"
chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.local"

# Enable extensions - deferring these commands to next login
# as they may require a running GNOME session
log_info "Creating script to enable extensions on next login..."
ENABLE_SCRIPT="/home/$REAL_USER/.config/autostart/enable-gnome-extensions.desktop"
mkdir -p "/home/$REAL_USER/.config/autostart/"

# Create the script to enable and configure extensions with colors
cat > "$SCRIPT_DIR/enable-gnome-extensions.sh" << 'EOF'
#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$HOME/.local/share/gnome-extensions-setup.log"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$HOME/.local/share/gnome-extensions-setup.log"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$HOME/.local/share/gnome-extensions-setup.log"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" | tee -a "$HOME/.local/share/gnome-extensions-setup.log"
}

# Wait for GNOME Shell to be fully loaded
sleep 10

log_info "Starting GNOME extensions configuration"

# Make sure extensions are enabled system-wide
if gsettings get org.gnome.shell disable-user-extensions | grep -q "true"; then
  log_warning "GNOME extensions are disabled system-wide! Enabling them now..."
  gsettings set org.gnome.shell disable-user-extensions false
  log_success "Extensions enabled system-wide."
fi

# Enable extensions
for extension in gTile@vibou unite@hardpixel.eu hidetopbar@mathieu.bidon.ca just-perfection-desktop@just-perfection; do
  log_info "Enabling extension: $extension"
  gnome-extensions enable "$extension" && log_success "Enabled $extension" || log_error "Failed to enable $extension"
done

log_info "Configuring extension settings"

# gTile
gsettings set org.gnome.shell.extensions.gtile.keybindings resize-left "['<Super>Left']"
gsettings set org.gnome.shell.extensions.gtile.keybindings resize-right "['<Super>Right']"
log_success "Configured gTile"

# Unite
gsettings set org.gnome.shell.extensions.unite hide-activities-button true
gsettings set org.gnome.shell.extensions.unite hide-window-titlebars 'always'
gsettings set org.gnome.shell.extensions.unite show-window-buttons 'always'
gsettings set org.gnome.shell.extensions.unite show-window-title 'never'
log_success "Configured Unite"

# Just Perfection
gsettings set org.gnome.shell.extensions.just-perfection animation true
gsettings set org.gnome.shell.extensions.just-perfection background-menu false
gsettings set org.gnome.shell.extensions.just-perfection dash false
gsettings set org.gnome.shell.extensions.just-perfection panel false
log_success "Configured Just Perfection"

# Hide Top Bar
gsettings set org.gnome.shell.extensions.hidetopbar mouse-sensitive true
gsettings set org.gnome.shell.extensions.hidetopbar pressure-threshold 100
gsettings set org.gnome.shell.extensions.hidetopbar pressure-timeout 1000
log_success "Configured Hide Top Bar"

log_success "GNOME extensions configuration completed"

# Remove this script from autostart
rm -f ~/.config/autostart/enable-gnome-extensions.desktop
log_info "Removed autostart entry"
EOF

chmod +x "$SCRIPT_DIR/enable-gnome-extensions.sh"
chown "$REAL_USER:$REAL_USER" "$SCRIPT_DIR/enable-gnome-extensions.sh"

# Create autostart entry
mkdir -p "/home/$REAL_USER/.config/autostart"
cat > "$ENABLE_SCRIPT" << EOF
[Desktop Entry]
Type=Application
Name=Enable GNOME Extensions
Exec=/home/$REAL_USER/.local/bin/enable-gnome-extensions.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Script to enable and configure GNOME extensions
EOF

chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.config/autostart"
chown "$REAL_USER:$REAL_USER" "$ENABLE_SCRIPT"

# Create directory for logs
mkdir -p "/home/$REAL_USER/.local/share"
chown "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.local/share"

log_header "Installation Complete"
log_success "GNOME extensions have been installed. They will be enabled and configured on your next login."
log_info "To restart GNOME Shell (on X11 only, not Wayland), press Alt+F2, type 'r', and press Enter."
log_info "You can also log out and log back in to activate the extensions."