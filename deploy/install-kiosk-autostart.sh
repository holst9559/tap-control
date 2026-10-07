#!/bin/bash
# Install desktop autostart for the Epiphany kiosk (more reliable than system systemd on Pi OS).

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
RC_XML="$LABWC_DIR/rc.xml"
MARKER_BEGIN="<!-- tap-control-kiosk-begin -->"
MARKER_END="<!-- tap-control-kiosk-end -->"

chmod +x "$REPO_DIR/deploy/start-kiosk.sh"
mkdir -p "$AUTOSTART_DIR"
cp "$REPO_DIR/deploy/tap-control-kiosk.desktop" "$AUTOSTART_DIR/"
echo "Installed $AUTOSTART_DIR/tap-control-kiosk.desktop"

install_labwc_fullscreen_rule() {
  mkdir -p "$LABWC_DIR"
  local rules
  rules=$(
    cat <<EOF
  $MARKER_BEGIN
  <windowRules>
    <windowRule identifier="org.gnome.Epiphany">
      <action name="ToggleFullscreen"/>
    </windowRule>
    <windowRule identifier="epiphany">
      <action name="ToggleFullscreen"/>
    </windowRule>
  </windowRules>
  $MARKER_END
EOF
  )

  if [ -f "$RC_XML" ] && grep -qF "$MARKER_BEGIN" "$RC_XML" 2>/dev/null; then
    echo "labwc fullscreen rule already installed in $RC_XML"
    return 0
  fi

  if [ ! -f "$RC_XML" ]; then
    cat >"$RC_XML" <<EOF
<?xml version="1.0"?>
<labwc_config>
$rules
</labwc_config>
EOF
    echo "Created $RC_XML with Epiphany fullscreen rule"
    return 0
  fi

  if grep -q '</labwc_config>' "$RC_XML"; then
    # Insert before closing root tag
    local tmp
    tmp="$(mktemp)"
    awk -v rules="$rules" '
      /<\/labwc_config>/ && !done {
        print rules
        done=1
      }
      { print }
    ' "$RC_XML" >"$tmp"
    mv "$tmp" "$RC_XML"
    echo "Merged Epiphany fullscreen rule into $RC_XML"
  else
    echo "warning: $RC_XML has unexpected format — add ToggleFullscreen windowRule manually"
  fi
}

# labwc (Bookworm/Trixie default compositor on Pi OS)
if [ -d "$LABWC_DIR" ] || command -v labwc >/dev/null 2>&1 || [ -d /etc/xdg/labwc ]; then
  install_labwc_fullscreen_rule

  AUTOSTART_FILE="$LABWC_DIR/autostart"
  mkdir -p "$LABWC_DIR"
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
echo "Optional (helps F11 on Wayland): sudo apt install -y wtype"
echo
echo "Test now with:"
echo "  $REPO_DIR/deploy/start-kiosk.sh"
echo "Log file: $USER_HOME/tap-control-kiosk.log"
echo "Then reboot."
