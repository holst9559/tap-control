#!/bin/bash
# Start a single Epiphany window fullscreen on the keezer UI.

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
LOCK_DIR="${TAP_CONTROL_KIOSK_LOCK_DIR:-$USER_HOME/.cache}"
LOCK="$LOCK_DIR/tap-control-kiosk.lock"
# Dedicated profile (not application-mode). Cleared each start → no session restore
# of leftover windows from earlier failed launches.
PROFILE="${TAP_CONTROL_KIOSK_PROFILE:-$USER_HOME/.config/epiphany-tap-kiosk}"

mkdir -p "$(dirname "$LOG")" "$LOCK_DIR"
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

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
  elif [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
  fi
fi

echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} URL=$URL"

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

kill_all_epiphany() {
  # Kill every Epiphany UI process for this user (not WebKit helpers by name alone).
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany ' 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany$' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'epiphany-browser' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'org.gnome.Epiphany' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -9 -u "$(id -un)" -f 'org.gnome.Epiphany' 2>/dev/null || true
  sleep 1
  local left
  left=$(pgrep -au "$(id -un)" -f '[e]piphany' 2>/dev/null | wc -l | tr -d ' ')
  echo "epiphany processes left after kill: ${left:-0}"
}

try_fullscreen() {
  local i
  for i in $(seq 1 12); do
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
  # Last resort once — F11 toggles
  if command -v wtype >/dev/null 2>&1; then
    wtype -k F11 2>/dev/null && echo "fullscreen via wtype F11" && return 0
  fi
  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null \
      && echo "fullscreen via xdotool F11" && return 0
  fi
  echo "could not force fullscreen (labwc rule may still apply)"
  return 0
}

wait_for_display || true
wait_for_app || true
kill_all_epiphany

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — install epiphany-browser"
  exit 1
fi

# Fresh profile every launch → exactly one window (no restored session stack).
rm -rf "$PROFILE"
mkdir -p "$PROFILE"

# Do NOT use --new-window (attaches to an existing instance and stacks windows).
# Do NOT use --application-mode (broken on this Epiphany without a full web-app install).
/usr/bin/epiphany --profile="$PROFILE" "$URL" &
EPID=$!
echo "epiphany pid=$EPID profile=$PROFILE url=$URL"

sleep 2
if ! kill -0 "$EPID" 2>/dev/null; then
  echo "error: epiphany exited immediately"
  wait "$EPID" || true
  exit 1
fi

hide_desktop_chrome
try_fullscreen &

# labwc 0.8.4+: Alt+Super+h → HideCursor (bound in install-kiosk-autostart.sh)
(
  sleep 8
  if command -v wtype >/dev/null 2>&1; then
    wtype -M alt -M logo -P h -m logo -m alt 2>/dev/null \
      && echo "hid cursor via labwc HideCursor (wtype A-W-h)" \
      || echo "warning: wtype HideCursor keybind failed"
  else
    echo "warning: wtype not installed — cursor may stay visible"
  fi
) &

wait "$EPID"
echo "epiphany exited: $?"
