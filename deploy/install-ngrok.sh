#!/bin/bash
# Install ngrok on the Raspberry Pi and publish the public kiosk URL.
# Admin CMS stays on the LAN (http://<pi>.local:3000/admin) — not via ngrok.
#
# Prerequisites:
#   - Free ngrok account → Authtoken from https://dashboard.ngrok.com/get-started/your-authtoken
#   - tap-control.service already running on this Pi
#
# Usage:
#   chmod +x deploy/install-ngrok.sh
#   ./deploy/install-ngrok.sh <NGROK_AUTHTOKEN>
#   ./deploy/install-ngrok.sh <NGROK_AUTHTOKEN> keezer.ngrok-free.app   # optional reserved domain

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUTHTOKEN="${1:-}"
RESERVED_DOMAIN="${2:-}"
CONFIG_DIR=/etc/ngrok
CONFIG_PATH="$CONFIG_DIR/ngrok.yml"
EXAMPLE_CFG="$REPO_DIR/deploy/ngrok/config.example.yml"
UNIT_SRC="$REPO_DIR/deploy/ngrok.service"
UNIT_DST=/etc/systemd/system/ngrok.service

if [[ -z "$AUTHTOKEN" ]]; then
  echo "Usage: $0 <NGROK_AUTHTOKEN> [reserved-domain]"
  echo "Get a token: https://dashboard.ngrok.com/get-started/your-authtoken"
  echo "Example: $0 2abc...xyz"
  echo "Example: $0 2abc...xyz keezer.ngrok-free.app"
  exit 1
fi

arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) ngrok_arch=arm64 ;;
  armv7l|armhf) ngrok_arch=arm ;;
  x86_64|amd64) ngrok_arch=amd64 ;;
  *)
    echo "Unsupported architecture: $arch"
    exit 1
    ;;
esac

echo "== download ngrok ($ngrok_arch) =="
tmp_tgz="$(mktemp --suffix=.tgz)"
curl -fsSL \
  "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ngrok_arch}.tgz" \
  -o "$tmp_tgz"
sudo tar -xzf "$tmp_tgz" -C /usr/local/bin ngrok
rm -f "$tmp_tgz"
sudo chmod 755 /usr/local/bin/ngrok
NGROK=/usr/local/bin/ngrok
"$NGROK" version

echo
echo "== write config =="
sudo mkdir -p "$CONFIG_DIR"
tmp_cfg="$(mktemp)"
AUTHTOKEN="$AUTHTOKEN" RESERVED_DOMAIN="$RESERVED_DOMAIN" EXAMPLE_CFG="$EXAMPLE_CFG" \
  python3 - "$tmp_cfg" <<'PY'
import os
import sys

out_path = sys.argv[1]
text = open(os.environ["EXAMPLE_CFG"], encoding="utf-8").read()
text = text.replace("NGROK_AUTHTOKEN", os.environ["AUTHTOKEN"])
reserved = os.environ.get("RESERVED_DOMAIN", "").strip()
if reserved:
    domain_url = reserved if reserved.startswith("https://") else f"https://{reserved}"
    text = text.replace(
        "# url: https://YOUR_RESERVED_DOMAIN.ngrok-free.app",
        f"url: {domain_url}",
    )
open(out_path, "w", encoding="utf-8").write(text)
PY

sudo cp "$tmp_cfg" "$CONFIG_PATH"
rm -f "$tmp_cfg"
sudo chmod 600 "$CONFIG_PATH"

echo
echo "== enable systemd =="
sudo cp "$UNIT_SRC" "$UNIT_DST"
sudo systemctl daemon-reload
sudo systemctl enable --now ngrok.service
sleep 3
sudo systemctl --no-pager --full status ngrok.service || true

echo
echo "Done."
echo "  Public URL:    check https://dashboard.ngrok.com/endpoints  (or journalctl below)"
echo "  LAN CMS only:  http://$(hostname).local:3000/admin"
echo "  Status:        sudo systemctl status ngrok --no-pager"
echo "  Logs:          sudo journalctl -u ngrok -n 40 --no-pager"
echo
if [[ -n "$RESERVED_DOMAIN" ]]; then
  host="${RESERVED_DOMAIN#https://}"
  echo "Verify /admin is blocked publicly:"
  echo "  curl -sI -H 'ngrok-skip-browser-warning: 1' https://${host}/admin | head -n1   # expect 404"
else
  echo "Free plan: open the ngrok dashboard for the current random https URL."
  echo "Optional static domain: re-run with a reserved hostname as the 2nd argument."
fi
echo
echo "If you use a custom (non-*.ngrok*) domain later, set on tap-control.service:"
echo "  Environment=TAP_CONTROL_PUBLIC_HOSTS=your.domain.example"
