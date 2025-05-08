#!/bin/bash
# Installs and configures GNOME extensions

set -e
echo "Installing GNOME extensions..."

# Determine the correct user
if [ "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(whoami)"
fi

echo "Installing extensions for user: $REAL_USER"

# Install required dependencies
apt update
apt install -y gnome-shell-extensions gnome-shell-extension-manager gnome-tweaks \
  git x11-utils gettext libglib2.0-dev unzip wget

# Check for npm, install if not found
if ! command -v npm &> /dev/null; then
  echo "Installing npm..."
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
  echo "Error: $1"
  echo "Cleaning up..."
  rm -rf "$TEMP_DIR"
  exit 1
}

echo "Installing gTile from source..."
su - "$REAL_USER" -c "cd $TEMP_DIR && \
  git clone https://github.com/gTile/gTile.git && \
  cd gTile && \
  npm ci && \
  npm run build:dist && \
  npm run install:extension" || handle_error "Failed to install gTile"

echo "Installing Unite..."
UNITE_VERSION="v82"
su - "$REAL_USER" -c "cd $TEMP_DIR && \
  wget https://github.com/hardpixel/unite-shell/releases/download/${UNITE_VERSION}/unite-${UNITE_VERSION}.zip -O unite.zip && \
  gnome-extensions install --force unite.zip" || handle_error "Failed to install Unite"

echo "Installing Hide Top Bar..."
if command -v apt &> /dev/null; then
  # Debian/Ubuntu method
  apt install -y gnome-shell-extension-autohidetopbar || handle_error "Failed to install Hide Top Bar via apt"
else
  # Source method
  su - "$REAL_USER" -c "cd $TEMP_DIR && \
    git clone https://gitlab.gnome.org/tuxor1337/hidetopbar.git && \
    cd hidetopbar && \
    make && \
    gnome-extensions install ./hidetopbar.zip" || handle_error "Failed to install Hide Top Bar from source"
fi

echo "Installing Just Perfection..."
su - "$REAL_USER" -c "cd $TEMP_DIR && \
  git clone https://gitlab.gnome.org/jrahmatzadeh/just-perfection.git && \
  cd just-perfection && \
  ./scripts/build.sh -i" || handle_error "Failed to install Just Perfection"

# Clean up
rm -rf "$TEMP_DIR"

# Create script directory if it doesn't exist
SCRIPT_DIR="/home/$REAL_USER/.local/bin"
mkdir -p "$SCRIPT_DIR"
chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.local"

# Enable extensions - deferring these commands to next login
# as they may require a running GNOME session
echo "Creating script to enable extensions on next login..."
ENABLE_SCRIPT="/home/$REAL_USER/.config/autostart/enable-gnome-extensions.desktop"
mkdir -p "/home/$REAL_USER/.config/autostart/"

# Create the script to enable and configure extensions
cat > "$SCRIPT_DIR/enable-gnome-extensions.sh" << 'EOF'
#!/bin/bash
# Wait for GNOME Shell to be fully loaded
sleep 10

# Function to log messages
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HOME/.local/share/gnome-extensions-setup.log"
}

log_message "Starting GNOME extensions configuration"

# Enable extensions
for extension in gTile@vibou unite@hardpixel.eu hidetopbar@mathieu.bidon.ca just-perfection-desktop@just-perfection; do
  log_message "Enabling extension: $extension"
  gnome-extensions enable "$extension" || log_message "Failed to enable $extension"
done

log_message "Configuring extension settings"

# gTile
gsettings set org.gnome.shell.extensions.gtile.keybindings resize-left "['<Super>Left']"
gsettings set org.gnome.shell.extensions.gtile.keybindings resize-right "['<Super>Right']"

# Unite
gsettings set org.gnome.shell.extensions.unite hide-activities-button true
gsettings set org.gnome.shell.extensions.unite hide-window-titlebars 'always'
gsettings set org.gnome.shell.extensions.unite show-window-buttons 'always'
gsettings set org.gnome.shell.extensions.unite show-window-title 'never'

# Just Perfection
gsettings set org.gnome.shell.extensions.just-perfection animation true
gsettings set org.gnome.shell.extensions.just-perfection background-menu false
gsettings set org.gnome.shell.extensions.just-perfection dash false
gsettings set org.gnome.shell.extensions.just-perfection panel false

# Hide Top Bar
gsettings set org.gnome.shell.extensions.hidetopbar mouse-sensitive true
gsettings set org.gnome.shell.extensions.hidetopbar pressure-threshold 100
gsettings set org.gnome.shell.extensions.hidetopbar pressure-timeout 1000

log_message "GNOME extensions configuration completed"

# Remove this script from autostart
rm -f ~/.config/autostart/enable-gnome-extensions.desktop
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

echo "GNOME extensions have been installed. They will be enabled and configured on your next login."
echo "To restart GNOME Shell (on X11 only, not Wayland), press Alt+F2, type 'r', and press Enter."
echo "You can also log out and log back in to activate the extensions."