#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (X11 openbox/LXDE and labwc).
# start-kiosk.sh uses flock, so multiple registrations are safe.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
OPENBOX_DIR="$USER_HOME/.config/openbox"
OPENBOX_AUTOSTART="$OPENBOX_DIR/autostart"
LXDE_DIR="$USER_HOME/.config/lxsession/LXDE-pi"
LXDE_AUTOSTART="$LXDE_DIR/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR" "$OPENBOX_DIR" "$LXDE_DIR" "$LABWC_DIR" "$USER_SYSTEMD_DIR"

echo "== Disable system systemd kiosk unit =="
if systemctl list-unit-files tap-control-kiosk.service >/dev/null 2>&1; then
  sudo systemctl disable --now tap-control-kiosk.service 2>/dev/null || true
fi

echo "== apt: unclutter =="
sudo apt-get update
sudo apt-get install -y unclutter

echo "== 1) XDG ~/.config/autostart =="
cat >"$AUTOSTART_DIR/tap-control-kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Tap Control Kiosk
Comment=Fullscreen Epiphany kiosk
Exec=/bin/bash $START_KIOSK
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
Hidden=false
EOF

cat >"$AUTOSTART_DIR/unclutter.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Unclutter
Comment=Hide mouse pointer
Exec=unclutter -idle 0 -root
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
EOF
echo "Installed $AUTOSTART_DIR/*.desktop"

echo "== 2) Openbox autostart (Pi OS X11 often uses this) =="
if [ -f "$OPENBOX_AUTOSTART" ]; then
  grep -vE 'start-kiosk\.sh|unclutter' "$OPENBOX_AUTOSTART" >"$OPENBOX_AUTOSTART.tmp" || true
  mv "$OPENBOX_AUTOSTART.tmp" "$OPENBOX_AUTOSTART"
fi
touch "$OPENBOX_AUTOSTART"
{
  echo "unclutter -idle 0 -root &"
  echo "$START_KIOSK &"
} >>"$OPENBOX_AUTOSTART"
chmod +x "$OPENBOX_AUTOSTART"
echo "Wrote $OPENBOX_AUTOSTART"

echo "== 3) LXDE-pi autostart =="
if [ -f /etc/xdg/lxsession/LXDE-pi/autostart ] && [ ! -f "$LXDE_AUTOSTART" ]; then
  cp /etc/xdg/lxsession/LXDE-pi/autostart "$LXDE_AUTOSTART"
fi
touch "$LXDE_AUTOSTART"
grep -vE 'start-kiosk\.sh|unclutter' "$LXDE_AUTOSTART" >"$LXDE_AUTOSTART.tmp" || true
mv "$LXDE_AUTOSTART.tmp" "$LXDE_AUTOSTART"
{
  echo "@unclutter -idle 0"
  echo "@$START_KIOSK"
} >>"$LXDE_AUTOSTART"
echo "Wrote $LXDE_AUTOSTART"

echo "== 4) systemd --user (runs with graphical login) =="
cat >"$USER_SYSTEMD_DIR/tap-control-kiosk.service" <<EOF
[Unit]
Description=Tap Control Epiphany kiosk
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XAUTHORITY=%h/.Xauthority
ExecStart=/bin/bash $START_KIOSK
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable tap-control-kiosk.service
echo "Enabled --user tap-control-kiosk.service"
# Allow user services at boot even before SSH (lingering)
loginctl enable-linger "$(id -un)" 2>/dev/null || true

echo "== 5) labwc autostart (if you switch back to Wayland) =="
cat >"$LABWC_AUTOSTART" <<EOF
#!/bin/sh
$START_KIOSK &
EOF
chmod +x "$LABWC_AUTOSTART"

echo
echo "Done. Verify files:"
echo "  ls -la ~/.config/autostart/"
echo "  cat ~/.config/openbox/autostart"
echo "  systemctl --user is-enabled tap-control-kiosk.service"
echo
echo "After reboot, if browser missing check:"
echo "  tail -40 ~/tap-control-kiosk.log"
echo "  systemctl --user status tap-control-kiosk.service --no-pager"
echo
echo "Reboot now: sudo reboot"
