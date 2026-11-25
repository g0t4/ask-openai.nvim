"""Centralized color/icon palette for the chat trace viewer.

Keeps all the aesthetic decisions in one place so the CLI dump and the
Textual viewer stay visually consistent.
"""

from __future__ import annotations

from rich.color import Color
from rich.style import Style
from rich.text import Text

# * THEME2 (proposed by chatgpt, try these)
# | Role | Color | Character |
# |---|---|---|
# | Background | `#1F2229` | your existing bg |
# | Normal text | `#C8CDD5` | soft gray |
# | Dim / metadata | `#737A86` | subdued |
# | Borders | `#3A3F4B` | visible, not distracting |
# | Primary accent | `#FF0071` | hot pink |
# | Blue | `#61AFEF` | cool contrast |
# | Cyan | `#56B6C2` | calmer informational |
# | Green | `#98C379` | success |
# | Yellow | `#D9B65D` | warning/timing |
# | Red | `#E06C75` | error |
# | Purple | `#B48EED` | secondary accent |
THEME2_ROLE_COLORS = {
    "system": "#B48EED",
    "user": "#56B6C2",
    "assistant": "#C8CDD5",
    "tool": "#61AFEF",
}
# reuse similar roles
THEME2_ROLE_COLORS["developer"] = THEME2_ROLE_COLORS["system"]
THEME2_ROLE_COLORS["user_raw"] = THEME2_ROLE_COLORS["user"]
THEME2_ROLE_COLORS["assistant_raw"] = THEME2_ROLE_COLORS["assistant"]

THEME2_SUCCESS_COLOR = "#98C379"
THEME2_WARNING_COLOR = "#D9B65D"
THEME2_FAILURE_COLOR = "#E06C75"

# * THEME1 Role -> accent color (used for section headers, labels, timing lines).
THEME1_ROLE_COLORS = {
    # color ideas from:
    # https://imagecolorpicker.com/color-code/76c6b5?skipGenerate=true
    "system": "#7677c6",
    "user": "#76c6b5",
    # "user": "#afc676",
    "assistant": "#c6b576",
    "tool": "#c67687",
}
THEME1_ROLE_COLORS["developer"] = THEME1_ROLE_COLORS["system"]
THEME1_ROLE_COLORS["user_raw"] = THEME1_ROLE_COLORS["user"]
THEME1_ROLE_COLORS["assistant_raw"] = THEME1_ROLE_COLORS["assistant"]

THEME1_BLACK = "#1F2229"
THEME1_WHITE = "#EEEEEE"

USE_ROLE_COLORS = THEME2_ROLE_COLORS

# Role -> icon shown next to the message header.
ROLE_ICONS = {
    "system": "📢",
    "developer": "💻",
    "user": "👤",
    "user_raw": "👤",

    # "assistant": "✨",
    "assistant": "🖕", # TODO I need a mode to toggle this for my own humor :)

    #   nf-oct-sparkle_fill \u
    #   nf-cod-sparkle \uec10

    "tool": "🔧",
}
import os

WES_VULGAR = os.getenv("WES_VULGAR", "").lower() in ("1", "true", "yes")
if not WES_VULGAR:
    ROLE_ICONS["assistant"] = "✨"
ROLE_ICONS["assistant_raw"] = ROLE_ICONS["assistant"]

# Tool name -> icon shown in the call title.
TOOL_ICONS = {
    "apply_patch": "📝",
    # "apply_patch": "󰷉 ",
    # "apply_patch": " ",

    #       
    # "run_command": "⚡", # I liked this too "zap"
    "run_command": " ", #   \uf489
    "run_process": " ", #   \uf489
    "run_bash": " ", #   \uf489

    "run_xonsh": "🐚",
    "run_in_neovim": " ", # \uf36f
    "semantic_grep": "󰕡 ",
    # "fetch": "󰜏",
    "fetch": "󰖟 ",
    "delegate": "🤝",
    "locate_anything": "🖼️",
    "screencap": "󰹑 ",
}


def get_success_color() -> str:
    return THEME2_SUCCESS_COLOR


def get_warning_color() -> str:
    return THEME2_WARNING_COLOR


def get_failure_color() -> str:
    return THEME2_FAILURE_COLOR


def get_pass_fail_color(successful) -> str:
    if successful:
        return get_success_color()
    return get_failure_color()


def role_color(role: str) -> str:
    """Return the accent color for a message role."""
    return USE_ROLE_COLORS.get(role.lower(), THEME1_WHITE)


def role_icon(role: str) -> str:
    """Return the icon for a message role."""
    return ROLE_ICONS.get(role.lower(), "•")


def tool_icon(name: str) -> str:
    """Return the icon for a tool call."""
    return TOOL_ICONS.get(name, "🔧")


def contrast_color_for(bg_color: str) -> str:
    """Pick black or white text for best contrast on the given background."""
    r, g, b = Color.parse(bg_color).get_truecolor()

    # Relative luminance (WCAG): 0 = black, 1 = white.
    def linearize(channel: int) -> float:
        channel /= 255
        return channel / 12.92 if channel <= 0.03928 else ((channel + 0.055) / 1.055) ** 2.4

    luminance = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    return THEME1_BLACK if luminance > 0.4 else THEME1_WHITE


def header_bar(title: str, color: str, width: int, font_color = None) -> Text:
    """Build a full-width section header bar.

    A colored ``pill`` holds the title (with a role icon), then a dim ``rule``
    fills the rest of the line so messages are cleanly separated without
    consuming three full lines.
    """
    r, g, b = Color.parse(color).get_truecolor()
    bg_hex = f"#{r:02x}{g:02x}{b:02x}"
    if font_color:
        font_color = font_color
    else:
        font_color = contrast_color_for(color)


    pill = Text(f" {title} ", style=Style(bgcolor=bg_hex, color=font_color, bold=True))
    rule_width = max(0, width - len(pill) - 1) # -1 for icons (some overflow a char and wrap the header)
    rule = Text(" " * rule_width, style="dim")
    return pill + rule
