#!/bin/bash
# Set up ydotool + ydotoold for pointer nudge on labwc < 0.8.4.
set -e

USER_NAME="$(id -un)"
USER_HOME="${HOME:-/home/$USER_NAME}"
RULE=/etc/udev/rules.d/99-tap-control-uinput.rules
SOCKET="${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}"

echo "Installing ydotool..."
sudo apt-get update
sudo apt-get install -y ydotool

echo "uinput udev rule..."
sudo tee "$RULE" >/dev/null <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF
sudo modprobe uinput || true
echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
sudo usermod -aG input "$USER_NAME" || true
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Starting ydotoold..."
sudo pkill ydotoold 2>/dev/null || true
sleep 0.5
# Run as root so /dev/uinput works; socket world-writable for the desktop user
sudo rm -f "$SOCKET"
sudo ydotoold --socket="$SOCKET" --socket-perm=0666 >/tmp/ydotoold.log 2>&1 &
sleep 1

if [ ! -S "$SOCKET" ]; then
  # Older ydotoold may not take --socket flags
  sudo pkill ydotoold 2>/dev/null || true
  sudo ydotoold >/tmp/ydotoold.log 2>&1 &
  sleep 1
fi

# Persist across reboot via a small systemd unit
sudo tee /etc/systemd/system/tap-control-ydotoold.service >/dev/null <<EOF
[Unit]
Description=ydotoold for tap-control kiosk cursor nudge
After=systemd-udev-settle.service

[Service]
Type=simple
ExecStart=/usr/bin/ydotoold --socket=$SOCKET --socket-perm=0666
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# If flags unsupported, fall back to bare ydotoold
if ! sudo systemd-analyze verify tap-control-ydotoold.service 2>/dev/null; then
  true
fi
sudo systemctl daemon-reload
if ! sudo systemctl enable --now tap-control-ydotoold.service 2>/dev/null; then
  sudo tee /etc/systemd/system/tap-control-ydotoold.service >/dev/null <<'EOF'
[Unit]
Description=ydotoold for tap-control kiosk cursor nudge

[Service]
Type=simple
ExecStart=/usr/bin/ydotoold
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now tap-control-ydotoold.service
fi

echo
echo "ydotool help (mousemove):"
YDOTOOL_SOCKET="$SOCKET" ydotool mousemove -h 2>&1 | head -40 || ydotool mousemove -h 2>&1 | head -40 || true

echo
echo "Test relative nudge (should move the pointer a bit):"
export YDOTOOL_SOCKET="$SOCKET"
if ydotool mousemove 80 80 2>/dev/null; then
  echo "OK: relative mousemove works"
elif ydotool mousemove -x 80 -y 80 2>/dev/null; then
  echo "OK: -x/-y mousemove works"
else
  echo "FAILED. Check: sudo journalctl -u tap-control-ydotoold -n 30 --no-pager"
  echo "And: cat /tmp/ydotoold.log"
  exit 1
fi

echo
echo "Reboot (or re-login for 'input' group), then reboot the kiosk."
echo "If this keeps failing, use X11+unclutter instead:"
echo "  ./deploy/install-x11-unclutter.sh"
