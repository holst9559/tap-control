#!/bin/bash
# Start Epiphany fullscreen on the keezer UI (meant for desktop autostart).

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/?lite=1}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
LOCK_DIR="${TAP_CONTROL_KIOSK_LOCK_DIR:-$USER_HOME/.cache}"
LOCK="$LOCK_DIR/tap-control-kiosk.lock"

mkdir -p "$(dirname "$LOG")" "$LOCK_DIR"
exec >>"$LOG" 2>&1
echo "---- $(date -Iseconds) kiosk start ----"

# One launcher only (XDG + labwc otherwise stack browsers)
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another start-kiosk.sh already holds $LOCK — exiting"
  exit 0
fi

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

echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR URL=$URL"

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

hide_desktop_chrome() {
  pkill -u "$(id -un)" -x wf-panel-pi 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanel 2>/dev/null || true
  echo "hid panel chrome (best-effort)"
}

kill_epiphany() {
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'epiphany-browser' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'org.gnome.Epiphany.WebApp_' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
}

kill_stray_epiphany() {
  local pid
  for pid in $(pgrep -u "$(id -un)" -x epiphany 2>/dev/null) \
             $(pgrep -u "$(id -un)" -x epiphany-browser 2>/dev/null); do
    if [ -n "${EPID:-}" ] && [ "$pid" = "$EPID" ]; then
      continue
    fi
    echo "killing stray epiphany pid=$pid"
    kill -9 "$pid" 2>/dev/null || true
  done
}

try_fullscreen() {
  local i
  # Retry: window may map late; F11 is toggle so only use if wmctrl fails.
  for i in $(seq 1 10); do
    sleep 2
    if command -v wmctrl >/dev/null 2>&1; then
      if wmctrl -x -r epiphany.Epiphany -b add,fullscreen 2>/dev/null \
        || wmctrl -x -r Epiphany -b add,fullscreen 2>/dev/null \
        || wmctrl -r :ACTIVE: -b add,fullscreen 2>/dev/null; then
        echo "fullscreen via wmctrl (attempt $i)"
        return 0
      fi
    fi
  done
  if command -v wtype >/dev/null 2>&1; then
    wtype -k F11 2>/dev/null && echo "fullscreen via wtype F11" && return 0
  fi
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null \
      && echo "fullscreen via xdotool F11" && return 0
  fi
  echo "could not force fullscreen via tools (labwc window rule may still apply)"
  return 0
}

wait_for_display || true
wait_for_app || true
sleep 2
kill_epiphany

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — install epiphany-browser"
  exit 1
fi

# Plain window + fullscreen. Avoid --application-mode on this Epiphany build
# (broken without a full portal web-app install; caused dual windows / crashes).
/usr/bin/epiphany --new-window "$URL" &
EPID=$!
echo "epiphany pid=$EPID url=$URL"

sleep 2
if kill -0 "$EPID" 2>/dev/null; then
  hide_desktop_chrome
fi

(
  for delay in 5 12 20; do
    sleep "$delay"
    kill_stray_epiphany
  done
) &

try_fullscreen &

wait "$EPID"
echo "epiphany exited: $?"
