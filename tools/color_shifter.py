#!/usr/bin/env python3
"""
Interactive color shifter for two colors.

Controls:
    Up        +step lightness
    Down      -step lightness
    Right     +step saturation
    Left      -step saturation
    Tab / t   toggle selected color
    1         select IN_HUE
    2         select OUT_HUE
    s         toggle step (10% <-> 5%)
    [         step -1   (min 1)
    ]         step +1   (max 100)
    r         reset selected color to its default
    q         quit (prints final hex values)
"""

import sys
import termios
import tty
import colorsys
import shutil


IN_DEFAULT = "#acadcf"
OUT_DEFAULT = "#cfacb4"
STEP = 10


def hex_to_hsl(hex_code):
    hex_code = hex_code.lstrip("#")
    r, g, b = (int(hex_code[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s * 100, l * 100


def hsl_to_rgb(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h / 360.0, l / 100.0, s / 100.0)
    return int(round(r * 255)), int(round(g * 255)), int(round(b * 255))


def hsl_to_hex(h, s, l):
    r, g, b = hsl_to_rgb(h, s, l)
    return "#{:02x}{:02x}{:02x}".format(r, g, b)


def clamp(v):
    return max(0, min(100, int(round(v))))


class Color:
    def __init__(self, name, default):
        self.name = name
        self.h, self.s, self.l = hex_to_hsl(default)
        self.default = default

    def hex(self):
        return hsl_to_hex(self.h, self.s, self.l)

    def rgb(self):
        return hsl_to_rgb(self.h, self.s, self.l)

    def reset(self):
        self.h, self.s, self.l = hex_to_hsl(self.default)


reset = "\x1b[0m"
bold = "\x1b[1m"
clear = "\x1b[2J\x1b[H"

def fg(r, g, b):
    return "\x1b[38;2;{};{};{}m".format(r, g, b)


def term_cols():
    return max(10, shutil.get_terminal_size((80, 24)).columns)


def trunc(s, cols):
    """Truncate a plain string to `cols` so it never wraps."""
    return s[:cols]


def emit(s=""):
    """Write a line, always returning the cursor to column 0 (raw-mode safe)."""
    sys.stdout.write(s + "\r\n")
    sys.stdout.flush()


def read_key():
    """Blocking read of a single key press. Returns a name or a character."""
    ch = sys.stdin.read(1)
    if ch == "\x1b":
        seq = sys.stdin.read(2)
        return {"[A": "up", "[B": "down", "[C": "right", "[D": "left"}.get(seq)
    return ch


def draw(in_color, out_color, active, step):
    print(clear, end="")
    cols = term_cols()
    title = trunc("Color Shifter  —  IN_HUE / OUT_HUE  (foreground color only)".strip(), cols - 1)
    emit(bold + " " + title + reset)
    help_ = trunc(" ↑/↓ lightness ±{}%   ←/→ saturation ±{}%   Tab/t switch   s 5/10   [ ] +/-1 step:{}   r reset   q quit".format(step, step, step), cols - 1)
    emit(help_)
    emit()

    selected = [in_color, out_color][active]
    for color in (in_color, out_color):
        marker = ">" if color is selected else " "
        r, g, b = color.rgb()
        # Foreground color only; strip leading/trailing whitespace from the label.
        plain = "{} {}  {}  H{} S{} L{}".format(
            marker, color.name, color.hex(), int(color.h), clamp(color.s), clamp(color.l)
        ).strip() + reset
        label = fg(r, g, b) + trunc(plain, cols - 1)
        emit(label)
    emit()


def main():
    in_color = Color("IN_HUE", IN_DEFAULT)
    out_color = Color("OUT_HUE", OUT_DEFAULT)
    active = 0
    step = STEP

    if not sys.stdin.isatty():
        print("Run this in an interactive terminal for arrow-key controls.")
        return

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        draw(in_color, out_color, active, step)
        while True:
            key = read_key()
            selected = (in_color, out_color)[active]
            change = False
            if key == "up":
                selected.l = clamp(selected.l + step)
                change = True
            elif key == "down":
                selected.l = clamp(selected.l - step)
                change = True
            elif key == "right":
                selected.s = clamp(selected.s + step)
                change = True
            elif key == "left":
                selected.s = clamp(selected.s - step)
                change = True
            elif key in ("\t", "t", "T"):
                active = 1 - active
                change = True
            elif key == "1":
                active = 0
                change = True
            elif key == "2":
                active = 1
                change = True
            elif key in ("s", "S"):
                step = 5 if step == 10 else 10
                change = True
            elif key == "[":
                step = max(1, step - 1)
                change = True
            elif key == "]":
                step = min(100, step + 1)
                change = True
            elif key in ("r", "R"):
                selected.reset()
                change = True
            elif key in ("q", "Q", "\x03"):
                break
            if change:
                draw(in_color, out_color, active, step)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    emit(reset)
    emit("IN_HUE = " + in_color.hex().strip())


if __name__ == "__main__":
    main()
