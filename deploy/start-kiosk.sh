#!/bin/bash
# Start a single fullscreen browser on the keezer UI (X11 Chromium preferred).

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
LOCK_DIR="${TAP_CONTROL_KIOSK_LOCK_DIR:-$USER_HOME/.cache}"
LOCK="$LOCK_DIR/tap-control-kiosk.lock"
CHROME_PROFILE="${TAP_CONTROL_KIOSK_CHROME_PROFILE:-$USER_HOME/.config/chromium-tap-kiosk}"
EPHY_PROFILE="${TAP_CONTROL_KIOSK_PROFILE:-$USER_HOME/.config/epiphany-tap-kiosk}"

mkdir -p "$(dirname "$LOG")" "$LOCK_DIR" "$CHROME_PROFILE" "$EPHY_PROFILE"
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

# Session bus is required by WebKit/GTK; openbox/SSH launches often omit it.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  elif command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    echo "started dbus via dbus-launch"
  fi
fi
echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-<empty>}"

USE_X11=0
if [ -S /tmp/.X11-unix/X0 ]; then
  USE_X11=1
  unset WAYLAND_DISPLAY
  export GDK_BACKEND=x11
  echo "using X11 DISPLAY=$DISPLAY GDK_BACKEND=$GDK_BACKEND"
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

find_browser() {
  # Prefer Chromium on X11 — Epiphany often starts WebKit with no mapped window.
  local c
  for c in chromium chromium-browser google-chrome; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  if [ -x /usr/bin/epiphany ]; then
    echo epiphany
    return 0
  fi
  if [ -x /usr/bin/epiphany-browser ]; then
    echo epiphany-browser
    return 0
  fi
  return 1
}

kill_browsers() {
  pkill -u "$(id -un)" -f 'chromium.*tap-kiosk|chromium-browser.*--kiosk|google-chrome.*--kiosk' 2>/dev/null || true
  pkill -u "$(id -un)" -x chromium 2>/dev/null || true
  pkill -u "$(id -un)" -x chromium-browser 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'org.gnome.Epiphany' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x chromium 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x chromium-browser 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  sleep 1
  echo "browser processes left: $(pgrep -cu "$(id -un)" -f '[c]hromium|[e]piphany' 2>/dev/null || echo 0)"
}

window_listed() {
  command -v wmctrl >/dev/null 2>&1 || return 1
  wmctrl -lx 2>/dev/null | grep -Ei 'chrom|epiphany|www-browser' >/dev/null
}

raise_and_fullscreen() {
  local i win
  for i in $(seq 1 20); do
    sleep 2
    if command -v wmctrl >/dev/null 2>&1; then
      echo "wmctrl -lx:" >>"$LOG"
      wmctrl -lx 2>/dev/null >>"$LOG" || true
      win=$(wmctrl -lx 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /chrom|epiphany|www-browser/ {print $1; exit}')
      if [ -n "$win" ]; then
        wmctrl -i -a "$win" 2>/dev/null || true
        wmctrl -i -r "$win" -b add,fullscreen 2>/dev/null || true
        wmctrl -i -r "$win" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "fullscreen via wmctrl id=$win (attempt $i)"
        return 0
      fi
    fi
    if command -v xdotool >/dev/null 2>&1; then
      if xdotool search --class chromium windowactivate --sync key F11 2>/dev/null \
        || xdotool search --class Chromium windowactivate --sync key F11 2>/dev/null \
        || xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null \
        || xdotool search --name 'localhost' windowactivate --sync key F11 2>/dev/null; then
        echo "fullscreen via xdotool F11 (attempt $i)"
        return 0
      fi
    fi
  done
  echo "could not raise/fullscreen browser window"
  return 1
}

start_chromium() {
  local bin="$1"
  mkdir -p "$CHROME_PROFILE"
  # --kiosk is real fullscreen; --app reduces chrome UI if kiosk unsupported.
  "$bin" \
    --user-data-dir="$CHROME_PROFILE" \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --ozone-platform=x11 \
    --disable-dev-shm-usage \
    --no-first-run \
    "$URL" &
  BPID=$!
  echo "chromium pid=$BPID bin=$bin profile=$CHROME_PROFILE"
}

start_epiphany() {
  local bin="$1"
  mkdir -p "$EPHY_PROFILE"
  export GDK_BACKEND=x11
  unset WAYLAND_DISPLAY
  "$bin" --profile="$EPHY_PROFILE" "$URL" &
  BPID=$!
  echo "epiphany pid=$BPID bin=$bin profile=$EPHY_PROFILE"
}

if ! wait_for_display; then
  echo "error: display never became ready"
  exit 1
fi
wait_for_app || true
kill_browsers

BROWSER="$(find_browser)" || {
  echo "error: no chromium/epiphany found — apt install chromium"
  exit 1
}
echo "selected browser=$BROWSER"

BPID=""
case "$BROWSER" in
  epiphany|epiphany-browser) start_epiphany "$BROWSER" ;;
  *) start_chromium "$BROWSER" ;;
esac

sleep 4
if ! kill -0 "$BPID" 2>/dev/null; then
  echo "error: $BROWSER exited immediately"
  wait "$BPID" || true
  # If chromium died instantly, try epiphany once.
  if [[ "$BROWSER" != epiphany* ]] && [ -x /usr/bin/epiphany ]; then
    echo "falling back to epiphany"
    start_epiphany /usr/bin/epiphany
    sleep 4
    if ! kill -0 "$BPID" 2>/dev/null; then
      echo "error: epiphany also exited immediately"
      wait "$BPID" || true
      exit 1
    fi
  else
    exit 1
  fi
fi
echo "$BROWSER still running after 4s (pid=$BPID)"

# Epiphany sometimes keeps a process with zero mapped windows — detect and swap.
if [ "$USE_X11" = 1 ] && ! window_listed; then
  echo "no browser window in wmctrl yet — waiting…"
  sleep 6
  echo "wmctrl -lx after wait:"
  wmctrl -lx 2>/dev/null || true
  if ! window_listed; then
    if [[ "$BROWSER" == epiphany* ]]; then
      for c in chromium chromium-browser; do
        if command -v "$c" >/dev/null 2>&1; then
          echo "epiphany has no X window — switching to $c"
          kill_browsers
          start_chromium "$c"
          sleep 5
          break
        fi
      done
    else
      echo "warning: chromium running but no wmctrl window yet (may still paint)"
    fi
  fi
fi

# Keep desktop panel — kiosk fullscreen covers it; killing lxpanel is flaky on Pi OS.
raise_and_fullscreen &

wait "$BPID"
code=$?
echo "browser exited: $code"
# Non-zero so systemd Restart=on-failure brings the kiosk back.
exit 1
