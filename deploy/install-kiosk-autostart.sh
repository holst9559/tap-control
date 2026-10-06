#!/bin/bash
# Install desktop autostart for the Epiphany kiosk (more reliable than system systemd on Pi OS).

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
WAYFIRE_INI="$USER_HOME/.config/wayfire.ini"

chmod +x "$REPO_DIR/deploy/start-kiosk.sh"
mkdir -p "$AUTOSTART_DIR"
cp "$REPO_DIR/deploy/tap-control-kiosk.desktop" "$AUTOSTART_DIR/"
echo "Installed $AUTOSTART_DIR/tap-control-kiosk.desktop"

# labwc (some Bookworm images)
if [ -d "$LABWC_DIR" ] || command -v labwc >/dev/null 2>&1; then
  mkdir -p "$LABWC_DIR"
  AUTOSTART_FILE="$LABWC_DIR/autostart"
  LINE="$REPO_DIR/deploy/start-kiosk.sh &"
  if [ ! -f "$AUTOSTART_FILE" ] || ! grep -qF "start-kiosk.sh" "$AUTOSTART_FILE" 2>/dev/null; then
    echo "$LINE" >>"$AUTOSTART_FILE"
    chmod +x "$AUTOSTART_FILE" 2>/dev/null || true
    echo "Appended kiosk line to $AUTOSTART_FILE"
  else
    echo "labwc autostart already references start-kiosk.sh"
  fi
fi

# Disable system kiosk unit if present — it often races the desktop session
if systemctl list-unit-files tap-control-kiosk.service >/dev/null 2>&1; then
  sudo systemctl disable --now tap-control-kiosk.service 2>/dev/null || true
  echo "Disabled system tap-control-kiosk.service (autostart replaces it)"
fi

echo
echo "Done. Ensure desktop auto-login is on:"
echo "  sudo raspi-config  →  System Options  →  Boot / Auto Login  →  Desktop"
echo
echo "Test now with:"
echo "  $REPO_DIR/deploy/start-kiosk.sh"
echo "Log file: $USER_HOME/tap-control-kiosk.log"
echo "Then reboot."
