#!/bin/bash
# Fullscreen Epiphany kiosk for the keezer UI (Pi Zero 2W / X11).

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
LOCK_DIR="${TAP_CONTROL_KIOSK_LOCK_DIR:-$USER_HOME/.cache}"
LOCK="$LOCK_DIR/tap-control-kiosk.lock"
PROFILE="${TAP_CONTROL_KIOSK_PROFILE:-$USER_HOME/.config/epiphany-tap-kiosk}"

mkdir -p "$(dirname "$LOG")" "$LOCK_DIR" "$PROFILE"
exec >>"$LOG" 2>&1
echo "---- $(date -Iseconds) kiosk start ----"

if ! command -v flock >/dev/null 2>&1; then
  echo "error: flock not found (apt install util-linux)"
  exit 1
fi

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another start-kiosk.sh already holds $LOCK — exiting"
  exit 0
fi

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HOME="$USER_HOME"
export GDK_BACKEND=x11
unset WAYLAND_DISPLAY
# Soften WebKit on 512MB-class Pis.
export WEBKIT_DISABLE_COMPOSITING_MODE="${WEBKIT_DISABLE_COMPOSITING_MODE:-1}"

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  elif command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    echo "started dbus via dbus-launch"
  fi
fi

echo "DISPLAY=$DISPLAY URL=$URL"

wait_for_display() {
  local i
  for i in $(seq 1 60); do
    if [ -S /tmp/.X11-unix/X0 ]; then
      echo "X socket ready"
      return 0
    fi
    sleep 1
  done
  echo "error: X socket not found"
  return 1
}

wait_for_app() {
  local i
  for i in $(seq 1 90); do
    if curl -sf "$URL" >/dev/null 2>&1; then
      echo "app ready at $URL"
      return 0
    fi
    sleep 1
  done
  echo "warning: $URL not reachable — starting browser anyway"
}

kill_epiphany() {
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  sleep 1
}

hide_desktop_chrome() {
  pkill -u "$(id -un)" -x wf-panel-pi 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanel 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanelx 2>/dev/null || true
}

raise_and_fullscreen() {
  local i win
  for i in $(seq 1 60); do
    hide_desktop_chrome
    sleep 2
    win=$(wmctrl -lx 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /epiphany/ {print $1; exit}')
    if [ -z "$win" ]; then
      continue
    fi
    wmctrl -i -a "$win" 2>/dev/null || true
    wmctrl -i -r "$win" -b add,fullscreen 2>/dev/null || true
    if [ "$i" -le 3 ] || [ $((i % 15)) -eq 0 ]; then
      echo "fullscreen id=$win (attempt $i)"
    fi
  done
}

if ! wait_for_display; then
  exit 1
fi
wait_for_app
kill_epiphany

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — apt install epiphany-browser"
  exit 1
fi

/usr/bin/epiphany --profile="$PROFILE" "$URL" &
EPID=$!
echo "epiphany pid=$EPID profile=$PROFILE"

sleep 5
if ! kill -0 "$EPID" 2>/dev/null; then
  echo "error: epiphany exited immediately"
  wait "$EPID" || true
  exit 1
fi

hide_desktop_chrome
echo "hid panel chrome"
raise_and_fullscreen &

wait "$EPID"
echo "epiphany exited: $?"
# Non-zero so systemd Restart=on-failure brings the kiosk back.
exit 1
