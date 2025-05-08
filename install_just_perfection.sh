#!/bin/bash
# Script to install Just Perfection GNOME extension

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

log_header "Installing Just Perfection GNOME extension..."

# Determine the correct user
if [ "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

log_info "Installing Just Perfection for user: ${CYAN}$REAL_USER${NC}"

# Install required dependencies
log_info "Checking for required dependencies..."
apt update
apt install -y git gettext libglib2.0-dev

# Create temporary directory for installation
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

# Function to check if extension is already installed
is_extension_installed() {
  local uuid=$1
  su - "$REAL_USER" -c "gnome-extensions list | grep -q \"$uuid\"" && return 0 || return 1
}

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

# Create a script to configure Just Perfection
log_info "Creating configuration script..."
CONFIG_SCRIPT="/home/$REAL_USER/.local/bin/configure-just-perfection.sh"
mkdir -p "/home/$REAL_USER/.local/bin"
chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.local"

cat > "$CONFIG_SCRIPT" << 'EOF'
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

log_info "Enabling Just Perfection extension..."
gnome-extensions enable just-perfection-desktop@just-perfection && \
  log_success "Enabled Just Perfection" || \
  log_error "Failed to enable Just Perfection"

log_info "Configuring Just Perfection..."
gsettings set org.gnome.shell.extensions.just-perfection animation true
gsettings set org.gnome.shell.extensions.just-perfection background-menu false
gsettings set org.gnome.shell.extensions.just-perfection dash false
gsettings set org.gnome.shell.extensions.just-perfection panel false
log_success "Just Perfection configured successfully"

log_info "NOTE: You may need to restart GNOME Shell for changes to take effect"
log_info "On X11: Press Alt+F2, type 'r', and press Enter"
log_info "On Wayland: Log out and log back in"
EOF

chmod +x "$CONFIG_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$CONFIG_SCRIPT"

log_header "Installation Complete"
log_success "Just Perfection has been installed."
log_info "To configure and enable Just Perfection, run: $CONFIG_SCRIPT"
log_warning "WARNING: Just Perfection might cause instability in some GNOME environments"
log_info "To restart GNOME Shell (on X11 only, not Wayland), press Alt+F2, type 'r', and press Enter."
log_info "You can also log out and log back in to activate the extension." 