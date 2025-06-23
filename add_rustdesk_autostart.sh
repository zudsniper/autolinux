#!/bin/bash
# Adds RustDesk flatpak to autostart configuration

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

# Determine the correct user
if [ "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

log_header "Adding RustDesk to autostart configuration..."
log_info "Configuring autostart for user: ${CYAN}$REAL_USER${NC}"

# Check if RustDesk flatpak is installed
if ! flatpak list --app | grep -q "com.rustdesk.RustDesk"; then
  log_error "RustDesk flatpak is not installed. Please install it first with:"
  log_error "  flatpak install -y flathub com.rustdesk.RustDesk"
  exit 1
fi

log_success "RustDesk flatpak is installed"

# Create autostart directory if it doesn't exist
AUTOSTART_DIR="/home/$REAL_USER/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.config"

# Create RustDesk autostart desktop entry
RUSTDESK_AUTOSTART="$AUTOSTART_DIR/com.rustdesk.RustDesk.desktop"

log_info "Creating autostart entry at: ${CYAN}$RUSTDESK_AUTOSTART${NC}"

cat > "$RUSTDESK_AUTOSTART" << 'EOF'
[Desktop Entry]
Type=Application
Name=RustDesk
GenericName=Remote Desktop
Comment=Remote Desktop (Autostart)
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=rustdesk com.rustdesk.RustDesk
Icon=com.rustdesk.RustDesk
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Categories=Network;RemoteAccess;
X-Flatpak=com.rustdesk.RustDesk
EOF

# Set proper ownership
chown "$REAL_USER:$REAL_USER" "$RUSTDESK_AUTOSTART"
chmod 644 "$RUSTDESK_AUTOSTART"

log_success "RustDesk autostart entry created successfully!"
log_info "RustDesk will now start automatically when you log in."
log_info "To disable autostart, you can:"
log_info "  - Delete the file: ${CYAN}$RUSTDESK_AUTOSTART${NC}"
log_info "  - Or use GNOME Tweaks → Startup Applications to manage it"

echo
log_header "Configuration Complete"
log_success "RustDesk has been added to your autostart configuration."
