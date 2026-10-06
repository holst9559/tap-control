# Tap Control

Keezer-övervakning för **Raspberry Pi Zero 2 WH**: räkna pulser från flödessensorer, visa kvarvarande fatvolym på en kioskdisplay, spela ljud när en tappning startar och hantera fat via ett **CMS i LAN** (ingen omdeploy när du byter fat).

## Hårdvara

### Flödessensorer (GREDIA GR-301P2)

Hall-effekt-pulsmetrar, DC 5–24 V, formel `F = 21 × Q` (L/min) → cirka **1260 pulser/L** före kalibrering.

| Kabel  | Anslut till                       |
| ------ | --------------------------------- |
| Röd    | Pi **5V** (delad)                 |
| Svart  | Pi **GND** (delad)                |
| Gul    | En GPIO per kran (open-collector) |

Standard BCM-pinnar (redigera i [`src/config.js`](src/config.js)):

| Kran | BCM |
| ---- | --- |
| 1    | 17  |
| 2    | 27  |
| 3    | 22  |

Aktivera interna pull-ups i mjukvara (redan gjort). Driv **inte** en hård 5V-signal in i GPIO.

Ingen HAT/ADC behövs. För permanent installation är en skruvplint-GPIO-breakout trevligare än lösa Dupont-kontakter. Placera Pi:n **bakom** keezeren (torrt), inte inne i kylan.

### Display & ljud

- mini-HDMI → skärm (Chromium-kiosk)
- Ljud via HDMI-högtalare eller USB-ljudkort (Pi Zero har ingen 3,5 mm-jack)

## Mjukvarustack

- Node.js 18+
- SQLite (`better-sqlite3`)
- Express REST + WebSocket
- `pigpio` på Pi:n (automatiskt **mock**-läge på Windows/dev eller med `TAP_CONTROL_MOCK=1`)

## Snabbstart (utvecklings-PC)

```bash
npm install
npm start
```

Öppna:

- Kiosk: http://localhost:3000/
- CMS: http://localhost:3000/admin — standard-PIN **`1234`**

Simulera tappningar utan hårdvara:

```bash
curl -X POST http://localhost:3000/api/debug/pulse/1 -H "Content-Type: application/json" -d "{\"count\":50}"
```

## Pi-installation

1. Flasha Raspberry Pi OS (desktop om du vill ha kiosk-webbläsaren).
2. I2C/SPI behövs inte; se till att Node 18+ är installerat.
3. Installera nativa beroenden:

```bash
sudo apt update
sudo apt install -y git build-essential python3 ffmpeg
# pigpio-daemon
sudo apt install -y pigpio
sudo systemctl enable --now pigpiod
```

4. Kopiera detta repo till Pi:n (t.ex. `/home/pi/tap_control`) och:

```bash
cd /home/pi/tap_control
npm install
# valfritt: lägg en kort ljudfil i sounds/default.wav
npm start
```

5. Systemd (redigera `User=` / sökvägar i unit-filerna vid behov):

```bash
sudo cp deploy/tap-control.service /etc/systemd/system/
sudo cp deploy/tap-control-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tap-control.service
sudo systemctl enable --now tap-control-kiosk.service
```

6. LAN-åtkomst: använd `http://<pi-hostname>.local:3000/admin` (Avahi/mDNS) eller Pi:ns IP. Appen binder `0.0.0.0:3000` som standard.

Valfritt värdnamn:

```bash
sudo hostnamectl set-hostname tap-control
```

## CMS (vardagsbruk)

På `/admin` kan du:

- Byta / koppla fat på varje kran
- Redigera kvarvarande volym, namn, status
- Kalibrera pulser/L per kran
- Ladda upp tappningsljud och sätta standard
- Byta kiosk/CMS färg- och säsongsteman (svenska säsonger ingår)
- Se tappningshistorik
- Byta CMS-PIN

Allt lagras i SQLite under `data/tap_control.db` — **ingen koddeploy** för att byta fat.

## Kodregler

- Inga nästlade funktionsdefinitioner — endast namngivna funktioner på toppnivå
- Formatera med Prettier: `npm run format`
- Håll justerbara värden i [`src/config.js`](src/config.js) eller CMS-inställningar för enkla handändringar

## Konfigurationsrattar

| Env / fil            | Syfte                                |
| -------------------- | ------------------------------------ |
| `PORT`               | HTTP-port (standard 3000)            |
| `HOST`               | Bindadress (standard `0.0.0.0`)      |
| `TAP_CONTROL_MOCK=1` | Tvinga mock-GPIO                     |
| `TAP_CONTROL_DB`     | SQLite-sökväg                        |
| `src/config.js`      | Standardpinnar, pulser/L, idle ms, PIN |

## Projektstruktur

Se `src/` för serverkod, `public/` för kiosk + CMS, `deploy/` för systemd-units.
