#!/bin/bash
# Start Epiphany fullscreen on the keezer UI (meant for desktop autostart).

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"

exec >>"$LOG" 2>&1
echo "---- $(date -Iseconds) kiosk start ----"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HOME="$USER_HOME"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
  fi
fi

echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

wait_for_display() {
  local i
  for i in $(seq 1 60); do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      echo "wayland socket ready"
      return 0
    fi
    if [ -S /tmp/.X11-unix/X0 ] || [ -S /tmp/.X11-unix/Xwayland0 ]; then
      echo "X socket ready"
      return 0
    fi
    sleep 1
  done
  echo "warning: no display socket found yet"
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
  return 1
}

try_fullscreen() {
  sleep 4
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -x -r epiphany.Epiphany -b add,fullscreen 2>/dev/null && echo "fullscreen via wmctrl" && return 0
    wmctrl -r :ACTIVE: -b add,fullscreen 2>/dev/null && echo "fullscreen via wmctrl active" && return 0
  fi
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null && echo "fullscreen via F11" && return 0
  fi
  echo "could not force fullscreen (open manually with F11 if needed)"
  return 0
}

wait_for_display || true
wait_for_app || true

pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
sleep 1

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — install epiphany-browser"
  exit 1
fi

# Newer Epiphany treats --application-mode's next arg as a .desktop file, not a URL.
/usr/bin/epiphany --new-window "$URL" &
EPID=$!
echo "epiphany pid=$EPID"

try_fullscreen &

wait "$EPID"
echo "epiphany exited: $?"
