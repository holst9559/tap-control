#!/bin/bash
# Start a single fullscreen Epiphany window on the keezer UI.
# Default is Epiphany (fits Pi Zero 2W / 512MB). Chromium only if forced:
#   TAP_CONTROL_KIOSK_BROWSER=chromium

URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
LOCK_DIR="${TAP_CONTROL_KIOSK_LOCK_DIR:-$USER_HOME/.cache}"
LOCK="$LOCK_DIR/tap-control-kiosk.lock"
EPHY_PROFILE="${TAP_CONTROL_KIOSK_PROFILE:-$USER_HOME/.config/epiphany-tap-kiosk}"
CHROME_PROFILE="${TAP_CONTROL_KIOSK_CHROME_PROFILE:-$USER_HOME/.config/chromium-tap-kiosk}"
# epiphany | chromium — default epiphany for low RAM
FORCE_BROWSER="${TAP_CONTROL_KIOSK_BROWSER:-epiphany}"

mkdir -p "$(dirname "$LOG")" "$LOCK_DIR" "$EPHY_PROFILE"
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

# WebKit/GTK need a session bus; systemd User= units often have none.
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
echo "URL=$URL FORCE_BROWSER=$FORCE_BROWSER"

# Soften WebKit on 512MB-class Pis (compositor often OOMs / blank window).
export WEBKIT_DISABLE_COMPOSITING_MODE="${WEBKIT_DISABLE_COMPOSITING_MODE:-1}"

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

find_epiphany() {
  if [ -x /usr/bin/epiphany ]; then
    echo /usr/bin/epiphany
    return 0
  fi
  if [ -x /usr/bin/epiphany-browser ]; then
    echo /usr/bin/epiphany-browser
    return 0
  fi
  if command -v epiphany >/dev/null 2>&1; then
    command -v epiphany
    return 0
  fi
  return 1
}

find_chromium() {
  local c
  for c in chromium chromium-browser google-chrome; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

kill_browsers() {
  pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'org.gnome.Epiphany' 2>/dev/null || true
  pkill -u "$(id -un)" -f 'chromium.*tap-kiosk|chromium-browser.*--kiosk' 2>/dev/null || true
  sleep 1
  pkill -9 -u "$(id -un)" -x epiphany 2>/dev/null || true
  pkill -9 -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
  sleep 1
  echo "browser processes left: $(pgrep -cu "$(id -un)" -f '[e]piphany|[c]hromium' 2>/dev/null || echo 0)"
}

window_listed() {
  command -v wmctrl >/dev/null 2>&1 || return 1
  wmctrl -lx 2>/dev/null | grep -Ei 'epiphany|chrom|www-browser' >/dev/null
}

hide_desktop_chrome() {
  # Same as before: panel must die or fullscreen leaves a strip of taskbar.
  pkill -u "$(id -un)" -x wf-panel-pi 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanel 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanelx 2>/dev/null || true
  echo "hid panel chrome (best-effort)"
}

raise_and_fullscreen() {
  local i win done_log=0
  # Keep re-applying; openbox/lxpanel often steal space after the first F11.
  for i in $(seq 1 60); do
    hide_desktop_chrome
    sleep 2
    if command -v wmctrl >/dev/null 2>&1; then
      if [ "$done_log" -eq 0 ]; then
        echo "wmctrl -lx:" >>"$LOG"
        wmctrl -lx 2>/dev/null >>"$LOG" || true
        done_log=1
      fi
      win=$(wmctrl -lx 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /epiphany|chrom|www-browser/ {print $1; exit}')
      if [ -n "$win" ]; then
        wmctrl -i -a "$win" 2>/dev/null || true
        wmctrl -i -r "$win" -b add,fullscreen 2>/dev/null || true
        wmctrl -i -r "$win" -b add,above 2>/dev/null || true
        wmctrl -i -r "$win" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        # Cover full screen geometry if WM ignores fullscreen hint.
        if command -v xdotool >/dev/null 2>&1; then
          local sw sh
          sw=$(xdotool getdisplaygeometry 2>/dev/null | awk '{print $1}')
          sh=$(xdotool getdisplaygeometry 2>/dev/null | awk '{print $2}')
          if [ -n "$sw" ] && [ -n "$sh" ]; then
            wmctrl -i -r "$win" -e "0,0,0,$sw,$sh" 2>/dev/null || true
          fi
        fi
        if [ "$i" -le 3 ] || [ $((i % 10)) -eq 0 ]; then
          echo "fullscreen via wmctrl id=$win (attempt $i)"
        fi
        continue
      fi
    fi
    if command -v xdotool >/dev/null 2>&1; then
      xdotool search --class epiphany windowactivate --sync key F11 2>/dev/null \
        || xdotool search --name 'localhost' windowactivate --sync key F11 2>/dev/null \
        || xdotool search --name 'Tap Control' windowactivate --sync key F11 2>/dev/null \
        || true
    fi
  done
  echo "fullscreen keep-alive finished"
}

start_epiphany() {
  local bin="$1"
  mkdir -p "$EPHY_PROFILE"
  export GDK_BACKEND=x11
  unset WAYLAND_DISPLAY
  # Reuse profile — wiping forced a 37-step migrator every boot.
  echo "starting epiphany bin=$bin profile=$EPHY_PROFILE"
  "$bin" --profile="$EPHY_PROFILE" "$URL" &
  BPID=$!
  echo "epiphany pid=$BPID"
}

start_chromium() {
  local bin="$1"
  mkdir -p "$CHROME_PROFILE"
  echo "warning: Chromium is heavy on 512MB — prefer Epiphany"
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
  echo "chromium pid=$BPID bin=$bin"
}

if ! wait_for_display; then
  echo "error: display never became ready"
  exit 1
fi
wait_for_app || true
kill_browsers

BPID=""
BROWSER=""
case "$FORCE_BROWSER" in
  chromium|chrome)
    BROWSER="$(find_chromium)" || {
      echo "error: chromium requested but not installed"
      exit 1
    }
    start_chromium "$BROWSER"
    ;;
  *)
    BROWSER="$(find_epiphany)" || {
      echo "error: epiphany not found — apt install epiphany-browser"
      exit 1
    }
    start_epiphany "$BROWSER"
    ;;
esac
echo "selected browser=$BROWSER"

sleep 5
if ! kill -0 "$BPID" 2>/dev/null; then
  echo "error: browser exited immediately"
  wait "$BPID" || true
  exit 1
fi
echo "browser still running after 5s (pid=$BPID)"

if [ "$USE_X11" = 1 ]; then
  if ! window_listed; then
    echo "no window in wmctrl yet — waiting for Epiphany to map…"
    sleep 10
    echo "wmctrl -lx after wait:"
    wmctrl -lx 2>/dev/null || true
    if ! window_listed; then
      echo "error: Epiphany process alive but no X11 window (check dbus/GDK_BACKEND above)"
      echo "hint: do NOT switch to Chromium on 512MB — fix Epiphany env instead"
      # Keep process; raise loop may still catch a late window. Do not fall back to Chromium.
    fi
  fi
fi

hide_desktop_chrome
raise_and_fullscreen &

wait "$BPID"
code=$?
echo "browser exited: $code"
exit 1
