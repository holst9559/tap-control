#!/bin/bash
# Start Epiphany fullscreen on the keezer UI (meant for desktop autostart).

# ?lite=1 = cheaper CSS/JS path for Pi Zero-class devices
URL="${TAP_CONTROL_KIOSK_URL:-http://localhost:3000/?lite=1}"
USER_HOME="${HOME:-/home/antonholst}"
LOG="${TAP_CONTROL_KIOSK_LOG:-$USER_HOME/tap-control-kiosk.log}"
# Must match Epiphany's web-app id (underscore, not hyphen).
APP_ID="${TAP_CONTROL_KIOSK_APP_ID:-org.gnome.Epiphany.WebApp_tap-control-kiosk}"
PROFILE="${TAP_CONTROL_KIOSK_PROFILE:-$USER_HOME/.local/share/$APP_ID}"
PORTAL_DESKTOP_DIR="$USER_HOME/.local/share/xdg-desktop-portal/applications"
APPS_DESKTOP_DIR="$USER_HOME/.local/share/applications"
PORTAL_DESKTOP="$PORTAL_DESKTOP_DIR/$APP_ID.desktop"
APPS_DESKTOP="$APPS_DESKTOP_DIR/$APP_ID.desktop"

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

hide_desktop_chrome() {
  pkill -u "$(id -un)" -x wf-panel-pi 2>/dev/null || true
  pkill -u "$(id -un)" -x lxpanel 2>/dev/null || true
  echo "hid panel chrome (best-effort)"
}

try_fullscreen() {
  sleep 4
  if command -v wmctrl >/dev/null 2>&1; then
    if wmctrl -x -r epiphany.Epiphany -b add,fullscreen 2>/dev/null \
      || wmctrl -r :ACTIVE: -b add,fullscreen 2>/dev/null; then
      echo "fullscreen via wmctrl"
      return 0
    fi
  fi
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

# Newer Epiphany looks up this desktop file via xdg-desktop-portal.
ensure_webapp_desktop() {
  mkdir -p "$PORTAL_DESKTOP_DIR" "$APPS_DESKTOP_DIR" "$PROFILE"
  # Marker file Epiphany expects inside web-app profiles
  : >"$PROFILE/.app"

  local desktop
  desktop=$(
    cat <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Tap Control
Comment=Keezer kiosk
Exec=epiphany --application-mode --profile=$PROFILE $URL
Icon=web-browser
Terminal=false
Categories=GNOME;GTK;Network;
StartupNotify=true
StartupWMClass=$APP_ID
NoDisplay=true
EOF
  )
  printf '%s\n' "$desktop" >"$PORTAL_DESKTOP"
  printf '%s\n' "$desktop" >"$APPS_DESKTOP"
  echo "wrote web-app desktop: $PORTAL_DESKTOP"
}

launch_epiphany() {
  /usr/bin/epiphany --application-mode --profile="$PROFILE" "$URL" &
  EPID=$!
  echo "epiphany application-mode pid=$EPID profile=$PROFILE"
  sleep 3
  if kill -0 "$EPID" 2>/dev/null; then
    return 0
  fi
  wait "$EPID" || true
  echo "application-mode failed (exit $?) — falling back to --new-window"
  /usr/bin/epiphany --new-window "$URL" &
  EPID=$!
  echo "epiphany new-window pid=$EPID"
  sleep 2
  kill -0 "$EPID" 2>/dev/null
}

wait_for_display || true
wait_for_app || true

pkill -u "$(id -un)" -x epiphany 2>/dev/null || true
pkill -u "$(id -un)" -x epiphany-browser 2>/dev/null || true
pkill -u "$(id -un)" -f '/usr/bin/epiphany' 2>/dev/null || true
# Also kill by web-app id process name if present
pkill -u "$(id -un)" -f "$APP_ID" 2>/dev/null || true
sleep 1

if [ ! -x /usr/bin/epiphany ]; then
  echo "error: /usr/bin/epiphany not found — install epiphany-browser"
  exit 1
fi

# Broken half-created web apps make Epiphany abort — recreate cleanly each boot.
rm -rf "$PROFILE"
ensure_webapp_desktop

if ! launch_epiphany; then
  echo "error: could not start epiphany"
  exit 1
fi

hide_desktop_chrome
try_fullscreen &

wait "$EPID"
echo "epiphany exited: $?"
