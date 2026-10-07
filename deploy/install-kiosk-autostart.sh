#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (X11).
# Primary (only) browser launcher: system systemd unit — reliable after reboot.
# Desktop files only start unclutter (cursor hide).

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(id -un)"
USER_HOME="${HOME:-$(getent passwd "$USER_NAME" | cut -d: -f6)}"
USER_UID="$(id -u)"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
OPENBOX_DIR="$USER_HOME/.config/openbox"
OPENBOX_AUTOSTART="$OPENBOX_DIR/autostart"
LXDE_DIR="$USER_HOME/.config/lxsession/LXDE-pi"
LXDE_AUTOSTART="$LXDE_DIR/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"
UNIT_DST="/etc/systemd/system/tap-control-kiosk.service"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR" "$OPENBOX_DIR" "$LXDE_DIR" "$LABWC_DIR"

echo "== apt: Epiphany + window tools (not Chromium — too heavy for 512MB) =="
sudo apt-get update
sudo apt-get install -y unclutter wmctrl xdotool epiphany-browser dbus-x11

echo "== 1) System systemd unit (browser launcher) =="
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
echo "Enabled: tap-control-kiosk.service -> $START_KIOSK"

echo "== 2) Remove competing browser autostarts (keep unclutter only) =="
# Old .desktop that launched start-kiosk would race the system unit.
rm -f "$AUTOSTART_DIR/tap-control-kiosk.desktop"
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

if [ -f "$OPENBOX_AUTOSTART" ]; then
  grep -vE 'start-kiosk\.sh|unclutter' "$OPENBOX_AUTOSTART" >"$OPENBOX_AUTOSTART.tmp" || true
  mv "$OPENBOX_AUTOSTART.tmp" "$OPENBOX_AUTOSTART"
fi
touch "$OPENBOX_AUTOSTART"
echo "unclutter -idle 0 -root &" >>"$OPENBOX_AUTOSTART"
chmod +x "$OPENBOX_AUTOSTART"

if [ ! -f "$LXDE_AUTOSTART" ]; then
  if [ -f /etc/xdg/lxsession/LXDE-pi/autostart ]; then
    cp /etc/xdg/lxsession/LXDE-pi/autostart "$LXDE_AUTOSTART"
  else
    cat >"$LXDE_AUTOSTART" <<'EOF'
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
EOF
  fi
fi
grep -vE 'start-kiosk\.sh|unclutter' "$LXDE_AUTOSTART" >"$LXDE_AUTOSTART.tmp" || true
mv "$LXDE_AUTOSTART.tmp" "$LXDE_AUTOSTART"
echo "@unclutter -idle 0" >>"$LXDE_AUTOSTART"

cat >"$LABWC_AUTOSTART" <<EOF
#!/bin/sh
unclutter -idle 0 -root &
EOF
chmod +x "$LABWC_AUTOSTART"

rm -f "$USER_HOME/.config/systemd/user/tap-control-kiosk.service"
if [ -S "${XDG_RUNTIME_DIR:-/run/user/$USER_UID}/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$USER_UID}/bus"
  systemctl --user disable tap-control-kiosk.service 2>/dev/null || true
  systemctl --user daemon-reload 2>/dev/null || true
fi

echo
echo "Starting kiosk now (if X is up)…"
sudo systemctl restart tap-control-kiosk.service || true
sleep 2
sudo systemctl --no-pager --full status tap-control-kiosk.service || true

echo
echo "Done. After reboot the system unit starts the browser."
echo "  sudo systemctl status tap-control-kiosk.service --no-pager"
echo "  journalctl -u tap-control-kiosk.service -n 50 --no-pager"
echo "  tail -40 $USER_HOME/tap-control-kiosk.log"
echo
echo "Reboot: sudo reboot"
