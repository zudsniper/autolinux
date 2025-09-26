#!/bin/bash
# Firefox Extensions Installation Helper
# Note: Firefox extensions cannot be automatically installed via script due to security restrictions.
# This script opens the extension URLs in Firefox for easy manual installation.

set -e

echo "============================================="
echo "  Firefox Extensions Installation Helper"
echo "============================================="
echo ""
echo "Firefox extensions cannot be automatically installed due to browser security."
echo "This script will open each extension page in Firefox for you to install manually."
echo ""
echo "Extensions to install:"
echo "  1. UBlock Origin - Ad blocker"
echo "  2. OneTab - Tab management"
echo "  3. Quick Tabs Ported - Tab switcher"
echo "  4. 1Password - Password manager"
echo ""

# Check if Firefox is installed
if ! command -v firefox &> /dev/null; then
    echo "❌ Firefox is not installed. Please install Firefox first."
    exit 1
fi

# Extension URLs
EXTENSIONS=(
    "https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/"
    "https://addons.mozilla.org/en-US/firefox/addon/onetab/"
    "https://addons.mozilla.org/en-US/firefox/addon/quick-tabs-ported/"
    "https://addons.mozilla.org/en-US/firefox/addon/1password-x-password-manager/"
)

EXTENSION_NAMES=(
    "UBlock Origin"
    "OneTab"
    "Quick Tabs Ported"
    "1Password"
)

# Ask user if they want to proceed
read -p "Do you want to open Firefox with the extension pages? [y/N]: " PROCEED

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    echo ""
    echo "You can manually install the extensions from these URLs:"
    for i in "${!EXTENSIONS[@]}"; do
        echo "  ${EXTENSION_NAMES[$i]}: ${EXTENSIONS[$i]}"
    done
    exit 0
fi

echo ""
echo "Opening Firefox with extension pages..."
echo "Please install each extension by clicking 'Add to Firefox' on each page."
echo ""

# Open Firefox with all extension pages
firefox "${EXTENSIONS[@]}" &

echo "✅ Firefox opened with extension installation pages."
echo ""
echo "Installation steps for each extension:"
echo "  1. Click 'Add to Firefox' button"
echo "  2. Click 'Add' in the confirmation dialog"
echo "  3. Configure the extension if needed"
echo ""
echo "After installing all extensions, you can close this terminal."