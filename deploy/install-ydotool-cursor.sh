#!/bin/bash
# Set up ydotool so start-kiosk.sh can nudge the pointer (labwc < 0.8.4 has no HideCursor).
set -e

USER_NAME="$(id -un)"
RULE=/etc/udev/rules.d/99-tap-control-uinput.rules

echo "Installing ydotool..."
sudo apt-get update
sudo apt-get install -y ydotool

echo "Allowing uinput access for group 'input'..."
sudo tee "$RULE" >/dev/null <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF

sudo modprobe uinput || true
echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null

if getent group input >/dev/null; then
  sudo usermod -aG input "$USER_NAME"
  echo "Added $USER_NAME to group 'input' (re-login required)"
fi

# Debian/RPi package unit name varies
if systemctl list-unit-files 'ydotoold.service' 2>/dev/null | grep -q ydotoold; then
  sudo systemctl enable --now ydotoold.service
  echo "Enabled ydotoold.service"
elif systemctl list-unit-files 'ydotool.service' 2>/dev/null | grep -q ydotool; then
  sudo systemctl enable --now ydotool.service
  echo "Enabled ydotool.service"
else
  echo "No ydotool systemd unit found — starting ydotoold in user autostart is needed."
  echo "Try manually: sudo ydotoold &"
fi

sudo udevadm control --reload-rules
sudo udevadm trigger

echo
echo "Done. Log out/in (or reboot), then test:"
echo "  ydotool mousemove --absolute -x 200 -y 200"
echo "If that moves the pointer, start-kiosk.sh can hide it via CSS after the nudge."
