#!/bin/bash
# Install kiosk autostart for Raspberry Pi OS (labwc --merge-config).
#
# - User ~/.config/labwc/autostart must contain ONLY tap-control lines
#   (never a copy of /etc/xdg/labwc/autostart — that doubles the toolbar).
# - Cursor hide uses labwc HideCursor (0.8.4+) via a keybind + wtype.

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="${HOME:-/home/antonholst}"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
LABWC_DIR="$USER_HOME/.config/labwc"
LABWC_AUTOSTART="$LABWC_DIR/autostart"
RC_XML="$LABWC_DIR/rc.xml"
MARKER_BEGIN="<!-- tap-control-kiosk-begin -->"
MARKER_END="<!-- tap-control-kiosk-end -->"
START_KIOSK="$REPO_DIR/deploy/start-kiosk.sh"

chmod +x "$START_KIOSK" "$REPO_DIR/deploy/install-kiosk-autostart.sh"
mkdir -p "$AUTOSTART_DIR" "$LABWC_DIR"

echo "== Disable systemd kiosk =="
if systemctl list-unit-files tap-control-kiosk.service >/dev/null 2>&1; then
  sudo systemctl disable --now tap-control-kiosk.service 2>/dev/null || true
  echo "Disabled tap-control-kiosk.service"
fi

echo "== Remove XDG kiosk desktop (labwc-only launcher) =="
rm -f "$AUTOSTART_DIR"/tap-control*.desktop
echo "Removed $AUTOSTART_DIR/tap-control*.desktop (if any)"

echo "== Cursor-hide tools =="
LABWC_VER="$(labwc -v 2>/dev/null || labwc --version 2>/dev/null || echo unknown)"
echo "labwc version: $LABWC_VER"
# wtype: HideCursor keybind on 0.8.4+; wlrctl: nudge pointer so CSS cursor:none applies on older labwc
sudo apt-get install -y wtype wlrctl 2>/dev/null || sudo apt-get install -y wtype || true
if ! command -v wlrctl >/dev/null 2>&1; then
  echo "note: wlrctl not in apt — on labwc < 0.8.4 cursor hide may need an OS/labwc upgrade"
fi

echo "== labwc autostart: kiosk + hide cursor =="
if [ -f "$LABWC_AUTOSTART" ]; then
  bak="$LABWC_AUTOSTART.bak.$(date +%Y%m%d%H%M%S)"
  cp "$LABWC_AUTOSTART" "$bak"
  echo "Backed up → $bak"
fi
cat >"$LABWC_AUTOSTART" <<EOF
#!/bin/sh
# tap-control extras only — panel/session stay in /etc/xdg/labwc/autostart
$START_KIOSK &
# labwc 0.8.4+: HideCursor + WarpCursor bound to Alt+Super+h
( sleep 10; wtype -M alt -M logo -P h -m logo -m alt ) &
EOF
chmod +x "$LABWC_AUTOSTART"
echo "Wrote $LABWC_AUTOSTART"

echo "== labwc rc.xml: fullscreen rules + HideCursor keybind =="
SNIPPET=$(
  cat <<EOF
  $MARKER_BEGIN
  <keyboard>
    <keybind key="A-W-h">
      <action name="HideCursor"/>
      <action name="WarpCursor" x="-1" y="-1"/>
    </keybind>
  </keyboard>
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

if [ -f "$RC_XML" ] && grep -qF "$MARKER_BEGIN" "$RC_XML" 2>/dev/null; then
  tmp="$(mktemp)"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 ~ begin { skip=1; next }
    $0 ~ end { skip=0; next }
    !skip { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
  echo "Removed old marked block from $RC_XML"
fi

# If a broken empty <openbox_config/> stub exists alone, start clean
if [ -f "$RC_XML" ] && grep -q '<openbox_config' "$RC_XML" \
  && ! grep -q '<labwc_config' "$RC_XML"; then
  bak="$RC_XML.bak.$(date +%Y%m%d%H%M%S)"
  mv "$RC_XML" "$bak"
  echo "Moved non-labwc rc.xml → $bak"
fi

if [ ! -f "$RC_XML" ]; then
  cat >"$RC_XML" <<EOF
<?xml version="1.0"?>
<labwc_config>
$SNIPPET
</labwc_config>
EOF
  echo "Created $RC_XML"
else
  tmp="$(mktemp)"
  awk -v rules="$SNIPPET" '
    /<\/labwc_config>/ && !done {
      print rules
      done=1
    }
    { print }
  ' "$RC_XML" >"$tmp"
  mv "$tmp" "$RC_XML"
  echo "Merged HideCursor + fullscreen rules into $RC_XML"
fi

echo
echo "Verify:"
echo "  cat ~/.config/labwc/autostart"
echo "  grep -A6 HideCursor ~/.config/labwc/rc.xml"
echo
if echo "$LABWC_VER" | grep -qE '0\.8\.[0-3]|0\.[0-7]\.'; then
  echo "Your labwc ($LABWC_VER) is older than 0.8.4 — HideCursor is NOT available."
  echo "start-kiosk.sh will nudge the pointer with wlrctl so CSS can hide it."
  echo "For a proper compositor hide, upgrade when possible:"
  echo "  sudo apt update && apt-cache policy labwc"
  echo "  sudo apt install -y labwc   # if a newer package exists"
fi
echo
echo "Then reboot."
