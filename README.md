# Tap Control

Keezer monitoring for **Raspberry Pi Zero 2 WH**: count pulses from flow sensors, show remaining keg volume on a kiosk display, play a sound when a pour starts, and manage kegs via a **LAN CMS** (no redeploy when you swap kegs).

## Hardware

### Flow sensors (GREDIA GR-301P2)

Hall-effect pulse meters, DC 5–24 V, formula `F = 21 × Q` (L/min) → about **1260 pulses/L** before calibration.

| Wire   | Connect to                        |
| ------ | --------------------------------- |
| Red    | Pi **5V** (shared)                |
| Black  | Pi **GND** (shared)               |
| Yellow | One GPIO per tap (open-collector) |

Default BCM pins (edit in [`src/config.js`](src/config.js)):

| Tap | BCM |
| --- | --- |
| 1   | 17  |
| 2   | 27  |
| 3   | 22  |

Enable internal pull-ups in software (already done). Do **not** drive a hard 5V signal into a GPIO.

No HAT/ADC needed. For a permanent install, a screw-terminal GPIO breakout is nicer than loose Dupont wires. Place the Pi **behind** the keezer (dry), not inside the cold space.

### Display & audio

- mini-HDMI → screen (Chromium/Epiphany kiosk)
- Audio via HDMI speakers or a USB sound card (Pi Zero has no 3.5 mm jack)

## Software stack

- Node.js 18+
- SQLite (`better-sqlite3`)
- Express REST + WebSocket
- `pigpio` on the Pi (automatic **mock** mode on Windows/dev or with `TAP_CONTROL_MOCK=1`)

## Quick start (dev PC)

```bash
# Skip the native pigpio build on desktop (optional package):
npm install --omit=optional
npm run dev
```

`npm run dev` sets `TAP_CONTROL_MOCK=1` — no pigpio needed. `npm start` also auto-mocks off-Pi (non-ARM Linux / macOS / Windows).

Open:

- Kiosk: http://localhost:3000/
- CMS: http://localhost:3000/admin — default PIN **`1234`**

Simulate pours without hardware:

```bash
curl -X POST http://localhost:3000/api/debug/pulse/1 -H "Content-Type: application/json" -d "{\"count\":50}"
```

## Pi install

1. Flash Raspberry Pi OS (desktop if you want the kiosk browser).
2. I2C/SPI are not required; make sure Node 18+ is installed.
3. Install native dependencies:

```bash
sudo apt update
sudo apt install -y git build-essential python3 ffmpeg pigpio
```

The Node `pigpio` package talks to GPIO **directly** (needs root) and must **not** run at the same time as the `pigpiod` daemon. Stop it if it is running:

```bash
sudo systemctl stop pigpiod
sudo systemctl disable pigpiod
```

4. Copy this repo to the Pi (e.g. `/home/pi/tap_control`) and:

```bash
cd /home/pi/tap_control
npm install
# optional: put a short sound file at sounds/default.wav
sudo npm start
```

(`sudo` is needed for GPIO. Without sensors: `TAP_CONTROL_MOCK=1 npm start`.)

5. Systemd (unit files assume `/home/antonholst/tap-control` — adjust as needed).
   The app runs as root for GPIO; the kiosk runs Epiphany as your normal user.

```bash
# Make sure pigpiod is not running (conflicts with Node pigpio)
sudo systemctl stop pigpiod
sudo systemctl disable pigpiod

# Check Node path — must match ExecStart in the .service file
which node

sudo cp deploy/tap-control.service /etc/systemd/system/
sudo cp deploy/tap-control-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tap-control.service
sudo systemctl enable --now tap-control-kiosk.service

# If something fails:
sudo systemctl status tap-control --no-pager
sudo journalctl -u tap-control -n 40 --no-pager
```

Kiosk (Epiphany fullscreen on **X11**): system systemd waits for the display, then `start-kiosk.sh` hides the panel and fullscreenes the browser. Cursor hide is via `unclutter`.

```bash
# Prefer X11 (Advanced Options → Wayland → X11) and desktop autologin:
sudo raspi-config

cd ~/tap-control
chmod +x deploy/install-kiosk-autostart.sh deploy/start-kiosk.sh
./deploy/install-kiosk-autostart.sh
# Log: ~/tap-control-kiosk.log
# Status: sudo systemctl status tap-control-kiosk.service --no-pager
```

The UI uses the normal themed layout (viewport-locked so meters stay visible).

6. LAN access: use `http://<pi-hostname>.local:3000/admin` (Avahi/mDNS) or the Pi’s IP. The app binds `0.0.0.0:3000` by default.

Optional hostname:

```bash
sudo hostnamectl set-hostname tap-control
```

## Public landing page (Cloudflare Tunnel)

The Pi stays on your LAN. A **Cloudflare Tunnel** publishes only the kiosk landing page (`/`) so guests outside your network can watch keg levels. **`/admin` is not exposed** — the CMS stays at `http://<pi-hostname>.local:3000/admin`.

Defense in depth:

1. `cloudflared` ingress returns 404 for `/admin`
2. The Node app rejects `/admin` and non-public APIs when the request carries a Cloudflare `Cf-Ray` header (see [`src/api/publicEdge.js`](src/api/publicEdge.js)). Public edge allows `GET /`, static kiosk assets, `GET /api/status`, `GET /api/settings`, and `/ws`.

### One-time setup on the Pi

1. Put a domain on Cloudflare DNS (free plan is enough).
2. With `tap-control.service` already running:

```bash
cd ~/tap-control
git pull
chmod +x deploy/install-cloudflared.sh
./deploy/install-cloudflared.sh keezer.example.com   # your hostname
```

The script installs `cloudflared`, creates a tunnel named `tap-control`, writes `/etc/cloudflared/config.yml`, adds a DNS CNAME, and enables `cloudflared.service`.

3. Check:

```bash
curl -sI https://keezer.example.com/ | head -n1          # 200
curl -sI https://keezer.example.com/admin | head -n1     # 404
# CMS still on LAN only:
curl -sI http://$(hostname).local:3000/admin | head -n1  # 200
```

Manual config template: [`deploy/cloudflared/config.example.yml`](deploy/cloudflared/config.example.yml). Systemd unit: [`deploy/cloudflared.service`](deploy/cloudflared.service).

No port forwarding on your router is required.

## CMS (day-to-day use)

At `/admin` you can:

- Swap / assign kegs on each tap
- Edit remaining volume, name, status
- Calibrate pulses/L per tap
- Upload pour sounds and set the default
- Change kiosk/CMS color and seasonal themes (Swedish seasons included)
- View pour history
- Change the CMS PIN

Everything is stored in SQLite under `data/tap_control.db` — **no code deploy** to swap kegs.

## Code style

- No nested function definitions — named top-level functions only
- Format with Prettier: `npm run format`
- Keep tunable values in [`src/config.js`](src/config.js) or CMS settings for easy hand edits

## Configuration knobs

| Env / file           | Purpose                                    |
| -------------------- | ------------------------------------------ |
| `PORT`               | HTTP port (default 3000)                   |
| `HOST`               | Bind address (default `0.0.0.0`)           |
| `TAP_CONTROL_MOCK=1` | Force mock GPIO (default in `npm run dev`) |
| `TAP_CONTROL_MOCK=0` | Force real pigpio even off-Pi              |
| `TAP_CONTROL_DB`     | SQLite path                                |
| `src/config.js`      | Default pins, pulses/L, idle ms, PIN       |

## Project layout

See `src/` for server code, `public/` for kiosk + CMS, `deploy/` for systemd units.
