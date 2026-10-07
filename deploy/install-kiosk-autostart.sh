#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (labwc --merge-config).
#
# - User ~/.config/labwc/autostart must contain ONLY the kiosk line
#   (never a copy of /etc/xdg/labwc/autostart — that doubles the toolbar).
# - Do NOT also install XDG ~/.config/autostart for the same script
#   (that doubles the browser). start-kiosk.sh also uses flock as a belt.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
LABWC_ENV="$LABWC_DIR/environment"
RC_XML="$LABWC_DIR/rc.xml"
MARKER_BEGIN="<!-- tap-control-kiosk-begin -->"
MARKER_END="<!-- tap-control-kiosk-end -->"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"
BLANK_CURSOR_PY="$REPO_DIR/deploy/install-blank-cursor.py"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR" "$LABWC_DIR"

echo "== Invisible cursor theme (hides pointer from boot, not only after mouse move) =="
python3 "$BLANK_CURSOR_PY"
# labwc reads environment at session start
if [ -f "$LABWC_ENV" ]; then
  grep -vE '^(XCURSOR_THEME|XCURSOR_SIZE)=' "$LABWC_ENV" >"$LABWC_ENV.tmp" || true
  mv "$LABWC_ENV.tmp" "$LABWC_ENV"
fi
{
  echo "XCURSOR_THEME=tap-control-blank"
  echo "XCURSOR_SIZE=24"
} >>"$LABWC_ENV"
echo "Wrote $LABWC_ENV"

echo "== Disable systemd kiosk =="
if systemctl list-unit-files tap-control-kiosk.service >/dev/null 2>&1; then
  sudo systemctl disable --now tap-control-kiosk.service 2>/dev/null || true
  echo "Disabled tap-control-kiosk.service"
fi

echo "== Remove XDG kiosk desktop (labwc-only launcher) =="
rm -f "$AUTOSTART_DIR"/tap-control*.desktop
echo "Removed $AUTOSTART_DIR/tap-control*.desktop (if any)"

echo "== labwc autostart: kiosk line only =="
if [ -f "$LABWC_AUTOSTART" ]; then
  bak="$LABWC_AUTOSTART.bak.$(date +%Y%m%d%H%M%S)"
  cp "$LABWC_AUTOSTART" "$bak"
  echo "Backed up → $bak"
fi
cat >"$LABWC_AUTOSTART" <<EOF
#!/bin/sh
# tap-control extras only — panel/session stay in /etc/xdg/labwc/autostart
$START_KIOSK &
EOF
chmod +x "$LABWC_AUTOSTART"
echo "Wrote $LABWC_AUTOSTART"

echo "== labwc fullscreen window rules =="
RULES=$(
  cat <<EOF
  $MARKER_BEGIN
  <windowRules>
    <windowRule identifier="org.gnome.Epiphany">
      <action name="ToggleFullscreen"/>
    </windowRule>
    <windowRule identifier="org.gnome.Epiphany.WebApp_tap-control-kiosk">
      <action name="ToggleFullscreen"/>
    </windowRule>
    <windowRule identifier="epiphany">
      <action name="ToggleFullscreen"/>
    </windowRule>
  </windowRules>
  $MARKER_END
EOF
)

# Replace previous marked block if present
if [ -f "$RC_XML" ] && grep -qF "$MARKER_BEGIN" "$RC_XML" 2>/dev/null; then
  tmp="$(mktemp)"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 ~ begin { skip=1; next }
    $0 ~ end { skip=0; next }
    !skip { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
  echo "Removed old marked fullscreen block from $RC_XML"
fi

if [ ! -f "$RC_XML" ]; then
  cat >"$RC_XML" <<EOF
<?xml version="1.0"?>
<labwc_config>
$RULES
</labwc_config>
EOF
  echo "Created $RC_XML"
else
  tmp="$(mktemp)"
  awk -v rules="$RULES" '
    /<\/labwc_config>/ && !done {
      print rules
      done=1
    }
    { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
  echo "Merged fullscreen rules into $RC_XML"
fi

echo
echo "Verify:"
echo "  cat ~/.config/labwc/autostart          # only start-kiosk.sh"
echo "  cat ~/.config/labwc/environment        # blank cursor theme"
echo "  ls ~/.config/autostart/tap-control* 2>/dev/null || echo '(no xdg kiosk desktop)'"
echo
echo "Test: $START_KIOSK"
echo "Log:  $USER_HOME/tap-control-kiosk.log"
echo "Reboot required for the blank cursor theme (labwc environment)."
