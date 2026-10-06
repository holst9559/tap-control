# Tap Control

Keezer tap monitor for a **Raspberry Pi Zero 2 WH**: count flow-sensor pulses, show remaining keg volume on a kiosk display, play a sound when a pour starts, and manage kegs from a **LAN CMS** (no redeploy when you swap a keg).

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

Enable internal pull-ups in software (already done). Do **not** drive a hard 5V signal into GPIO.

No HAT/ADC required. For a permanent install, a screw-terminal GPIO breakout is nicer than bare Dupont jumpers. Keep the Pi **behind** the keezer (dry), not inside the cold cabinet.

### Display & audio

- mini-HDMI → monitor (Chromium kiosk)
- Audio via HDMI speakers or a USB sound card (Pi Zero has no 3.5 mm jack)

## Software stack

- Node.js 18+
- SQLite (`better-sqlite3`)
- Express REST + WebSocket
- `pigpio` on the Pi (automatic **mock** mode on Windows/dev or when `TAP_CONTROL_MOCK=1`)

## Quick start (dev PC)

```bash
npm install
npm start
```

Open:

- Kiosk: http://localhost:3000/
- CMS: http://localhost:3000/admin — default PIN **`1234`**

Simulate pours without hardware:

```bash
curl -X POST http://localhost:3000/api/debug/pulse/1 -H "Content-Type: application/json" -d "{\"count\":50}"
```

## Pi install

1. Flash Raspberry Pi OS (desktop if you want the kiosk browser).
2. Enable I2C/SPI not required; ensure Node 18+ is installed.
3. Install native deps:

```bash
sudo apt update
sudo apt install -y git build-essential python3 ffmpeg
# pigpio daemon
sudo apt install -y pigpio
sudo systemctl enable --now pigpiod
```

4. Copy this repo to the Pi (e.g. `/home/pi/tap_control`) and:

```bash
cd /home/pi/tap_control
npm install
# optional: drop a short clip at sounds/default.wav
npm start
```

5. Systemd (edit `User=` / paths in the unit files if needed):

```bash
sudo cp deploy/tap-control.service /etc/systemd/system/
sudo cp deploy/tap-control-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tap-control.service
sudo systemctl enable --now tap-control-kiosk.service
```

6. LAN access: use `http://<pi-hostname>.local:3000/admin` (Avahi/mDNS) or the Pi’s IP. The app binds `0.0.0.0:3000` by default.

Optional hostname:

```bash
sudo hostnamectl set-hostname tap-control
```

## CMS (day-to-day)

At `/admin` you can:

- Swap / assign kegs on each tap
- Edit remaining volume, names, status
- Calibrate pulses/L per tap
- Upload pour sounds and set defaults
- View pour history
- Change the CMS PIN

All of that is stored in SQLite under `data/tap_control.db` — **no code deploy** to change a keg.

## Coding rules

- No nested function definitions — top-level named functions only
- Format with Prettier: `npm run format`
- Keep tunables in [`src/config.js`](src/config.js) or CMS settings for easy hand edits

## Config knobs

| Env / file           | Purpose                              |
| -------------------- | ------------------------------------ |
| `PORT`               | HTTP port (default 3000)             |
| `HOST`               | Bind address (default `0.0.0.0`)     |
| `TAP_CONTROL_MOCK=1` | Force mock GPIO                      |
| `TAP_CONTROL_DB`     | SQLite path                          |
| `src/config.js`      | Default pins, pulses/L, idle ms, PIN |

## Project layout

See `src/` for server code, `public/` for kiosk + CMS, `deploy/` for systemd units.
