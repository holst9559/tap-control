#!/bin/bash
# X11 cursor hide via unclutter (the classic Pi forum approach).
# Also ensures the kiosk XDG autostart entry exists (labwc autostart is ignored on X11).
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$REPO_DIR/deploy/install-kiosk-autostart.sh"
