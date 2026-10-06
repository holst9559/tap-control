#!/bin/bash
# Start Epiphany in application mode on the keezer UI, then try to go fullscreen.

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
  fi
fi

wait_for_app() {
  local i
  for i in $(seq 1 90); do
    if curl -sf "$URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "[kiosk] warning: $URL not reachable yet — starting browser anyway" >&2
  return 1
}

try_fullscreen() {
  sleep 3
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -x -r epiphany.Epiphany -b add,fullscreen 2>/dev/null && return 0
    wmctrl -r :ACTIVE: -b add,fullscreen 2>/dev/null && return 0
  fi
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null && return 0
  fi
  return 0
}

wait_for_app || true

pkill -u "$(id -un)" -f 'epiphany.*localhost:3000' 2>/dev/null || true
sleep 1

/usr/bin/epiphany --application-mode "$URL" &
EPID=$!

try_fullscreen &

wait "$EPID"
