#!/bin/bash
# Script to disable all GNOME extensions and reset configurations

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

log_header "Resetting GNOME extensions and configurations..."

log_info "This script will:"
log_info "1. Disable all GNOME extensions"
log_info "2. Reset extension-specific configurations"
log_info "3. Restart GNOME Shell (on X11)"

log_warning "Your desktop environment will briefly reset during this process."
read -p "$(echo -e "${YELLOW}Continue? (y/n)${NC} ")" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info "Operation cancelled."
  exit 0
fi

# Determine if we're on X11 or Wayland
SESSION_TYPE=$(echo $XDG_SESSION_TYPE)
log_info "Session type: $SESSION_TYPE"

# Disable all extensions
log_header "Disabling all extensions..."

# First, enable user extensions system-wide setting (needed to manage them)
gsettings set org.gnome.shell disable-user-extensions false
log_success "Enabled user extensions system-wide setting"

# Get a list of all enabled extensions
ENABLED_EXTENSIONS=$(gnome-extensions list --enabled 2>/dev/null || echo "")

if [ -n "$ENABLED_EXTENSIONS" ]; then
  log_info "Found enabled extensions:"
  echo "$ENABLED_EXTENSIONS"
  
  # Disable each extension
  while read -r ext; do
    log_info "Disabling: $ext"
    gnome-extensions disable "$ext" 2>/dev/null || log_warning "Could not disable $ext"
  done <<< "$ENABLED_EXTENSIONS"
  log_success "All extensions have been disabled"
else
  log_info "No enabled extensions found"
fi

# Reset extension-specific configurations
log_header "Resetting extension configurations..."

# Reset Unite settings
log_info "Resetting Unite settings..."
dconf reset -f /org/gnome/shell/extensions/unite/ 2>/dev/null || log_warning "Could not reset Unite settings"

# Reset Tiling Shell settings
log_info "Resetting Tiling Shell settings..."
dconf reset -f /org/gnome/shell/extensions/tilingshell/ 2>/dev/null || log_warning "Could not reset Tiling Shell settings"

# Reset Just Perfection settings
log_info "Resetting Just Perfection settings..."
dconf reset -f /org/gnome/shell/extensions/just-perfection/ 2>/dev/null || log_warning "Could not reset Just Perfection settings"

# Reset Hide Top Bar settings
log_info "Resetting Hide Top Bar settings..."
dconf reset -f /org/gnome/shell/extensions/hidetopbar/ 2>/dev/null || log_warning "Could not reset Hide Top Bar settings"

# Also try to reset gTile if it was installed
log_info "Resetting gTile settings..."
dconf reset -f /org/gnome/shell/extensions/gtile/ 2>/dev/null || log_warning "Could not reset gTile settings"

# General reset for all shell extensions
log_info "Resetting general GNOME shell extension settings..."
dconf reset -f /org/gnome/shell/enabled-extensions 2>/dev/null || log_warning "Could not reset enabled extensions"

log_success "Extension configurations have been reset"

# Restart GNOME Shell if on X11
if [ "$SESSION_TYPE" = "x11" ]; then
  log_header "Restarting GNOME Shell..."
  log_info "Attempting to restart GNOME Shell (only works on X11)"
  
  # Use dbus-send to restart GNOME Shell
  dbus-send --type=method_call --dest=org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Eval string:'Meta.restart("Restarting…")' >/dev/null 2>&1 || \
  log_warning "Could not restart GNOME Shell automatically. Please restart manually by:"
  log_info "Press Alt+F2, type 'r', and press Enter"
else
  log_warning "Automatic GNOME Shell restart not available on Wayland."
  log_warning "Please log out and log back in to complete the reset."
fi

log_header "Reset Complete"
log_success "Your GNOME extensions have been disabled and configurations reset."
log_info "If you're still experiencing issues, please log out and log back in." 