#!/bin/bash
# Start a single Epiphany window fullscreen on the keezer UI.

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

# Prefer X11 when its socket exists (Pi switched to X11 + unclutter).
if [ -S /tmp/.X11-unix/X0 ]; then
  unset WAYLAND_DISPLAY
  echo "using X11 DISPLAY=$DISPLAY"
else
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
      export WAYLAND_DISPLAY=wayland-0
    elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
      export WAYLAND_DISPLAY=wayland-1
    fi
  fi
  echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
fi
echo "URL=$URL"

wait_for_display() {
  local i
  for i in $(seq 1 60); do
    if [ -S /tmp/.X11-unix/X0 ] || [ -S /tmp/.X11-unix/Xwayland0 ]; then
      echo "X socket ready"
      return 0
    fi
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      echo "wayland socket ready"
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

kill_all_epiphany() {
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'epiphany-browser' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'org.gnome.Epiphany' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  sleep 1
  echo "epiphany processes left: $(pgrep -cu "$(id -un)" -f '[e]piphany' 2>/dev/null || echo 0)"
}

raise_and_fullscreen() {
  local i
  for i in $(seq 1 15); do
    sleep 2
    if command -v wmctrl >/dev/null 2>&1; then
      # List matches for debugging
      wmctrl -lx 2>/dev/null | grep -i ephy >>"$LOG" || true
      if wmctrl -x -a epiphany.Epiphany 2>/dev/null \
        || wmctrl -x -a Epiphany 2>/dev/null \
        || wmctrl -a "Tap Control" 2>/dev/null \
        || wmctrl -a "Keezer" 2>/dev/null \
        || wmctrl -a "localhost" 2>/dev/null; then
        wmctrl -r :ACTIVE: -b add,fullscreen 2>/dev/null || true
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "raised/fullscreen via wmctrl (attempt $i)"
        return 0
      fi
      # Fallback: any window containing epiphany in WM_CLASS
      local win
      win=$(wmctrl -lx 2>/dev/null | awk '/[Ee]piphany/ {print $1; exit}')
      if [ -n "$win" ]; then
        wmctrl -i -a "$win" 2>/dev/null || true
        wmctrl -i -r "$win" -b add,fullscreen 2>/dev/null || true
        echo "fullscreen via wmctrl id=$win (attempt $i)"
        return 0
      fi
    fi
    if command -v xdotool >/dev/null 2>&1; then
      if xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null \
        || xdotool search --name 'localhost' windowactivate --sync key F11 2>/dev/null; then
        echo "fullscreen via xdotool F11 (attempt $i)"
        return 0
      fi
    fi
  done
  echo "could not raise/fullscreen epiphany window"
  return 0
}

wait_for_display || true
wait_for_app || true
kill_all_epiphany

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — install epiphany-browser"
  exit 1
fi

# Reuse profile (wiping forced a 37-step migrator every boot and delayed the UI).
mkdir -p "$PROFILE"

/usr/bin/epiphany --profile="$PROFILE" "$URL" &
EPID=$!
echo "epiphany pid=$EPID profile=$PROFILE url=$URL"

sleep 3
if ! kill -0 "$EPID" 2>/dev/null; then
  echo "error: epiphany exited immediately"
  wait "$EPID" || true
  exit 1
fi
echo "epiphany still running after 3s"

hide_desktop_chrome
raise_and_fullscreen &

wait "$EPID"
echo "epiphany exited: $?"
