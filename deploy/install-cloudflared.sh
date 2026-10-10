#!/bin/bash
# Install cloudflared on the Raspberry Pi and wire a public kiosk hostname.
# Admin CMS stays on the LAN (http://<pi>.local:3000/admin) — not via the tunnel.
#
# Prerequisites:
#   - A Cloudflare account with a domain on Cloudflare DNS
#   - tap-control.service already running on this Pi
#
# Usage:
#   chmod +x deploy/install-cloudflared.sh
#   ./deploy/install-cloudflared.sh keezer.example.com

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOSTNAME_ARG="${1:-}"
CONFIG_DIR=/etc/cloudflared
BIN_PATH=/usr/local/bin/cloudflared
UNIT_SRC="$REPO_DIR/deploy/cloudflared.service"
UNIT_DST=/etc/systemd/system/cloudflared.service
EXAMPLE_CFG="$REPO_DIR/deploy/cloudflared/config.example.yml"

if [[ -z "$HOSTNAME_ARG" ]]; then
  echo "Usage: $0 <public-hostname>"
  echo "Example: $0 keezer.example.com"
  exit 1
fi

arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) cf_arch=arm64 ;;
  armv7l|armhf) cf_arch=arm ;;
  x86_64|amd64) cf_arch=amd64 ;;
  *)
    echo "Unsupported architecture: $arch"
    exit 1
    ;;
esac

echo "== download cloudflared ($cf_arch) =="
tmp_deb="$(mktemp --suffix=.deb)"
curl -fsSL \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}.deb" \
  -o "$tmp_deb"
sudo dpkg -i "$tmp_deb" || sudo apt-get install -f -y
rm -f "$tmp_deb"

# Prefer /usr/bin/cloudflared from the package; fall back if needed.
if [[ -x /usr/bin/cloudflared ]]; then
  CLOUDFLARED=/usr/bin/cloudflared
elif [[ -x "$BIN_PATH" ]]; then
  CLOUDFLARED="$BIN_PATH"
else
  echo "cloudflared binary not found after install"
  exit 1
fi

# Point the systemd unit at the installed binary.
sudo mkdir -p "$CONFIG_DIR"
sudo cp "$UNIT_SRC" "$UNIT_DST"
sudo sed -i "s|/usr/local/bin/cloudflared|$CLOUDFLARED|g" "$UNIT_DST"

echo
echo "== Cloudflare login (browser) =="
echo "A login URL will appear. Complete it, then return here."
sudo "$CLOUDFLARED" tunnel login

echo
echo "== create tunnel =="
TUNNEL_NAME="tap-control"
if ! sudo "$CLOUDFLARED" tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
  sudo "$CLOUDFLARED" tunnel create "$TUNNEL_NAME"
fi

TUNNEL_ID="$(sudo "$CLOUDFLARED" tunnel list | awk -v name="$TUNNEL_NAME" '$2 == name { print $1; exit }')"
if [[ -z "$TUNNEL_ID" ]]; then
  echo "Could not resolve tunnel id for name=$TUNNEL_NAME"
  exit 1
fi
echo "Tunnel id: $TUNNEL_ID"

CRED_SRC=""
for candidate in \
  "/root/.cloudflared/${TUNNEL_ID}.json" \
  "$HOME/.cloudflared/${TUNNEL_ID}.json" \
  "/etc/cloudflared/${TUNNEL_ID}.json"; do
  if [[ -f "$candidate" ]]; then
    CRED_SRC="$candidate"
    break
  fi
done

if [[ -z "$CRED_SRC" ]]; then
  echo "Credentials JSON for $TUNNEL_ID not found. Look under ~/.cloudflared/"
  exit 1
fi

sudo cp "$CRED_SRC" "$CONFIG_DIR/${TUNNEL_ID}.json"
sudo chmod 600 "$CONFIG_DIR/${TUNNEL_ID}.json"

echo
echo "== write config =="
sudo sed \
  -e "s/TUNNEL_ID/${TUNNEL_ID}/g" \
  -e "s/keezer\\.example\\.com/${HOSTNAME_ARG}/g" \
  "$EXAMPLE_CFG" | sudo tee "$CONFIG_DIR/config.yml" >/dev/null

echo
echo "== DNS route =="
sudo "$CLOUDFLARED" tunnel route dns "$TUNNEL_NAME" "$HOSTNAME_ARG"

echo
echo "== enable systemd =="
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared.service
sleep 2
sudo systemctl --no-pager --full status cloudflared.service || true

echo
echo "Done."
echo "  Public kiosk:  https://${HOSTNAME_ARG}/"
echo "  LAN CMS only:  http://$(hostname).local:3000/admin"
echo "  Status:        sudo systemctl status cloudflared --no-pager"
echo "  Logs:          sudo journalctl -u cloudflared -n 40 --no-pager"
echo
echo "Verify /admin is blocked publicly:"
echo "  curl -sI https://${HOSTNAME_ARG}/admin | head -n1   # expect 404"
