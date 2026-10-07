#!/usr/bin/env python3
"""Install a fully transparent cursor theme for labwc / Wayland kiosk use."""

from __future__ import annotations

import os
import struct
import sys

THEME_NAME = "tap-control-blank"
CURSOR_NAMES = (
    "left_ptr",
    "default",
    "arrow",
    "top_left_arrow",
    "left_ptr_watch",
    "pointer",
    "hand1",
    "hand2",
    "xterm",
    "text",
    "crosshair",
    "watch",
    "sb_h_double_arrow",
    "sb_v_double_arrow",
    "fleur",
    "pirate",
)


def write_blank_xcursor(path: str, size: int = 24) -> None:
    """Write a valid Xcursor file with one fully transparent image."""
    image_type = 0xFFFD0002
    image_header_size = 36
    width = size
    height = size
    pixels = b"\x00" * (width * height * 4)  # BGRA, fully transparent

    image = struct.pack(
        "<IIIIIIIII",
        image_header_size,
        image_type,
        size,
        1,  # version
        width,
        height,
        0,  # xhot
        0,  # yhot
        50,  # delay ms
    )
    image += pixels

    file_header_size = 16
    ntoc = 1
    toc_position = file_header_size + 12  # header + one TOC entry

    data = b"Xcur"
    data += struct.pack("<III", file_header_size, 0x00010000, ntoc)
    data += struct.pack("<III", image_type, size, toc_position)
    data += image

    with open(path, "wb") as fh:
        fh.write(data)


def main() -> int:
    home = os.environ.get("HOME") or os.path.expanduser("~")
    theme_root = os.path.join(home, ".local", "share", "icons", THEME_NAME)
    cursors_dir = os.path.join(theme_root, "cursors")
    os.makedirs(cursors_dir, exist_ok=True)

    with open(os.path.join(theme_root, "index.theme"), "w", encoding="utf-8") as fh:
        fh.write(
            f"[Icon Theme]\nName={THEME_NAME}\n"
            "Comment=Invisible cursor for tap-control kiosk\nInherits=\n"
        )

    primary = os.path.join(cursors_dir, "left_ptr")
    write_blank_xcursor(primary)
    for name in CURSOR_NAMES:
        if name == "left_ptr":
            continue
        target = os.path.join(cursors_dir, name)
        try:
            if os.path.lexists(target):
                os.remove(target)
            os.symlink("left_ptr", target)
        except OSError:
            write_blank_xcursor(target)

    default_dir = os.path.join(home, ".local", "share", "icons", "default")
    os.makedirs(default_dir, exist_ok=True)
    with open(os.path.join(default_dir, "index.theme"), "w", encoding="utf-8") as fh:
        fh.write(f"[Icon Theme]\nName=Default\nInherits={THEME_NAME}\n")

    print(f"Installed blank cursor theme at {theme_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
