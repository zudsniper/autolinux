#!/bin/bash
# Install + configure GNOME extensions from extensions.gnome.org.
#
# Kept for backwards compatibility: the logic now lives in modules/*.sh and is
# run by install.sh. Extra arguments are passed through, e.g. --dry-run.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh" --only gnome-extensions --yes "$@"
