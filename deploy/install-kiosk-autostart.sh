#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (X11 and/or labwc).
# start-kiosk.sh uses flock, so registering both XDG + labwc is safe.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
RC_XML="$LABWC_DIR/rc.xml"
LXDE_AUTOSTART_DIR="$USER_HOME/.config/lxsession/LXDE-pi"
LXDE_AUTOSTART="$LXDE_AUTOSTART_DIR/autostart"
MARKER_BEGIN="<!-- tap-control-kiosk-begin -->"
MARKER_END="<!-- tap-control-kiosk-end -->"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR"

echo "== Disable systemd kiosk unit =="
if systemctl list-unit-files tap-control-kiosk.service >/dev/null 2>&1; then
  sudo systemctl disable --now tap-control-kiosk.service 2>/dev/null || true
  echo "Disabled tap-control-kiosk.service"
fi

echo "== XDG autostart (required for X11 / LXDE-pi) =="
cat >"$AUTOSTART_DIR/tap-control-kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Tap Control Kiosk
Comment=Fullscreen Epiphany on localhost:3000
Exec=/bin/bash $START_KIOSK
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
Hidden=false
EOF
echo "Installed $AUTOSTART_DIR/tap-control-kiosk.desktop"

echo "== unclutter (X11 cursor hide — forum recipe: unclutter -idle 0) =="
sudo apt-get update
sudo apt-get install -y unclutter
cat >"$AUTOSTART_DIR/unclutter.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Unclutter
Comment=Hide mouse pointer for kiosk
Exec=unclutter -idle 0 -root
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
EOF
echo "Installed $AUTOSTART_DIR/unclutter.desktop"

# Optional: classic LXDE-pi autostart line (older Pi OS X11 images)
if [ -d /etc/xdg/lxsession/LXDE-pi ] || [ -d "$LXDE_AUTOSTART_DIR" ]; then
  mkdir -p "$LXDE_AUTOSTART_DIR"
  if [ ! -f "$LXDE_AUTOSTART" ] && [ -f /etc/xdg/lxsession/LXDE-pi/autostart ]; then
    cp /etc/xdg/lxsession/LXDE-pi/autostart "$LXDE_AUTOSTART"
    echo "Copied system LXDE-pi autostart → $LXDE_AUTOSTART"
  fi
  if [ -f "$LXDE_AUTOSTART" ]; then
    grep -vE 'start-kiosk\.sh|unclutter' "$LXDE_AUTOSTART" >"$LXDE_AUTOSTART.tmp" || true
    mv "$LXDE_AUTOSTART.tmp" "$LXDE_AUTOSTART"
    echo "@unclutter -idle 0" >>"$LXDE_AUTOSTART"
    echo "@$START_KIOSK" >>"$LXDE_AUTOSTART"
    echo "Updated $LXDE_AUTOSTART"
  fi
fi

echo "== labwc extras (only used if you boot Wayland/labwc again) =="
mkdir -p "$LABWC_DIR"
if [ -f "$LABWC_AUTOSTART" ]; then
  bak="$LABWC_AUTOSTART.bak.$(date +%Y%m%d%H%M%S)"
  cp "$LABWC_AUTOSTART" "$bak"
fi
# Keep labwc autostart minimal — flock prevents double browser with XDG
cat >"$LABWC_AUTOSTART" <<EOF
#!/bin/sh
$START_KIOSK &
EOF
chmod +x "$LABWC_AUTOSTART"
echo "Wrote $LABWC_AUTOSTART"

# Fullscreen window rules (harmless on X11)
SNIPPET=$(
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
  tmp="$(mktemp)"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 ~ begin { skip=1; next }
    $0 ~ end { skip=0; next }
    !skip { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
fi
if [ ! -f "$RC_XML" ]; then
  cat >"$RC_XML" <<EOF
<?xml version="1.0"?>
<labwc_config>
$SNIPPET
</labwc_config>
EOF
elif grep -q '</labwc_config>' "$RC_XML"; then
  tmp="$(mktemp)"
  awk -v rules="$SNIPPET" '
    /<\/labwc_config>/ && !done { print rules; done=1 }
    { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
fi

echo
echo "Done for X11 + Wayland."
echo "  Kiosk:     ~/.config/autostart/tap-control-kiosk.desktop"
echo "  Cursor:    ~/.config/autostart/unclutter.desktop  (unclutter -idle 0)"
echo
echo "Confirm desktop is X11:"
echo "  echo \$XDG_SESSION_TYPE   # should say x11 after graphical login"
echo
echo "Test now:"
echo "  unclutter -idle 0 -root &"
echo "  $START_KIOSK"
echo "Then reboot."
