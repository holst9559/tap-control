#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (X11).
# Browser: system systemd unit. Cursor: XDG unclutter autostart.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(id -un)"
USER_HOME="${HOME:-$(getent passwd "$USER_NAME" | cut -d: -f6)}"
USER_UID="$(id -u)"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"
UNIT_DST="/etc/systemd/system/tap-control-kiosk.service"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR"

echo "== apt =="
sudo apt-get update
sudo apt-get install -y unclutter wmctrl epiphany-browser dbus-x11

echo "== systemd unit (browser) =="
sudo tee "$UNIT_DST" >/dev/null <<EOF
[Unit]
Description=Tap Control kiosk browser
After=graphical.target network-online.target tap-control.service
Wants=network-online.target
Wants=tap-control.service

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority
Environment=HOME=$USER_HOME
Environment=XDG_RUNTIME_DIR=/run/user/$USER_UID
Environment=GDK_BACKEND=x11
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 180); do [ -S /tmp/.X11-unix/X0 ] && [ -f $USER_HOME/.Xauthority ] && exit 0; sleep 1; done; echo "X not ready"; exit 1'
ExecStart=/bin/bash $START_KIOSK
Restart=on-failure
RestartSec=8
TimeoutStartSec=240

[Install]
WantedBy=graphical.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable tap-control-kiosk.service

echo "== unclutter (cursor) =="
# Drop old competing browser autostarts / Wayland leftovers.
rm -f "$AUTOSTART_DIR/tap-control-kiosk.desktop"
rm -f "$USER_HOME/.config/systemd/user/tap-control-kiosk.service"
for f in \
  "$USER_HOME/.config/openbox/autostart" \
  "$USER_HOME/.config/lxsession/LXDE-pi/autostart" \
  "$USER_HOME/.config/labwc/autostart"; do
  if [ -f "$f" ]; then
    grep -vE 'start-kiosk\.sh' "$f" >"$f.tmp" 2>/dev/null || true
    mv "$f.tmp" "$f"
  fi
done

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

echo
sudo systemctl restart tap-control-kiosk.service || true
sleep 2
sudo systemctl --no-pager --full status tap-control-kiosk.service || true
echo
echo "Done."
echo "  sudo systemctl status tap-control-kiosk.service --no-pager"
echo "  tail -40 $USER_HOME/tap-control-kiosk.log"
