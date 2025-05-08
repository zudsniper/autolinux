#!/bin/bash
# Installs and configures GNOME extensions

set -e
echo "Installing GNOME extensions..."

# Install GNOME Shell extension tools
apt install -y gnome-shell-extensions gnome-shell-extension-manager gnome-tweaks

# Function to install GNOME extension
install_extension() {
    local uuid=$1
    local version=${2:-latest}
    local download_url="https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version}"
    
    echo "Installing extension: ${uuid}"
    local tmp_dir=$(mktemp -d)
    wget -q "${download_url}" -O "${tmp_dir}/extension.zip"
    mkdir -p ~/.local/share/gnome-shell/extensions/${uuid}
    unzip -q "${tmp_dir}/extension.zip" -d ~/.local/share/gnome-shell/extensions/${uuid}
    rm -rf "${tmp_dir}"
}

# Install required extensions
install_extension "gTile@vibou"
install_extension "unite@hardpixel.eu"
install_extension "just-perfection-desktop@just-perfection"
install_extension "hidetopbar@mathieu.bidon.ca"

# Configure extensions (will apply on next login)
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

echo "GNOME extensions setup completed"