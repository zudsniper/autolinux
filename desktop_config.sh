#!/bin/bash
set -e
echo "Configuring desktop environment..."

# Function to configure user settings (must run as actual user, not root)
configure_desktop() {
  # Set dark theme
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
  
  # Configure sidebar (dock)
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'
  gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
  
  # Clear current favorites
  gsettings set org.gnome.shell favorite-apps "[]"
  
  # Set pinned apps in specific order
  gsettings set org.gnome.shell favorite-apps "[
    'firefox.desktop', 
    'google-chrome.desktop', 
    'kitty.desktop', 
    'gnome-system-monitor.desktop', 
    'com.discordapp.Discord.desktop', 
    'com.spotify.Client.desktop', 
    'cursor.desktop', 
    'code.desktop', 
    'com.valvesoftware.Steam.desktop'
  ]"
}

# Create a script to be run by the user (not root)
cat > /home/jason/setup_desktop.sh << 'EOF'
#!/bin/bash
# Configure desktop settings
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
gsettings set org.gnome.shell favorite-apps "[]"
gsettings set org.gnome.shell favorite-apps "[
  'firefox.desktop', 
  'google-chrome.desktop', 
  'kitty.desktop', 
  'gnome-system-monitor.desktop', 
  'com.discordapp.Discord.desktop', 
  'com.spotify.Client.desktop', 
  'cursor.desktop', 
  'code.desktop', 
  'com.valvesoftware.Steam.desktop'
]"
EOF

# Make it executable and set ownership
chmod +x /home/jason/setup_desktop.sh
chown jason:jason /home/jason/setup_desktop.sh

# Create autostart entry to run on first login
mkdir -p /home/jason/.config/autostart
cat > /home/jason/.config/autostart/first-login-setup.desktop << EOF
[Desktop Entry]
Type=Application
Name=First Login Setup
Exec=/home/jason/setup_desktop.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Terminal=false
Comment=Setup desktop environment on first login
EOF

chown -R jason:jason /home/jason/.config/autostart