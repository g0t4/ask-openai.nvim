"""Centralized color/icon palette for the chat trace viewer.

Keeps all the aesthetic decisions in one place so the CLI dump and the
Textual viewer stay visually consistent.
"""

from __future__ import annotations

from rich.color import Color
from rich.style import Style
from rich.text import Text


# Role -> accent color (used for section headers, labels, timing lines).
ROLE_COLORS = {
    "system": "magenta",
    "developer": "cyan",
    "user": "green",
    "user_raw": "green",
    "assistant": "yellow",
    "assistant_raw": "yellow",
    "tool": "red",
}

# Role -> icon shown next to the message header.
ROLE_ICONS = {
    "system": "📢",
    "developer": "💻",
    "user": "👤",
    "user_raw": "⌨️",
    "assistant": "🧠",
    "assistant_raw": "⚙️",
    "tool": "🔧",
}

# Tool name -> icon shown in the call title.
TOOL_ICONS = {
    "apply_patch": "📝",
    "run_command": "⚡",
    "run_process": "⚡",
    "run_xonsh": "🐚",
    "run_in_neovim": "📟",
    "semantic_grep": "🔍",
    "fetch": "🌐",
    "delegate": "🤝",
    "locate_anything": "🖼️",
    "screencap": "📸",
}


def role_color(role: str) -> str:
    """Return the accent color for a message role."""
    return ROLE_COLORS.get(role.lower(), "white")


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
    return "black" if luminance > 0.4 else "white"


def header_bar(title: str, color: str, width: int) -> Text:
    """Build a full-width section header bar.

    A colored ``pill`` holds the title (with a role icon), then a dim ``rule``
    fills the rest of the line so messages are cleanly separated without
    consuming three full lines.
    """
    r, g, b = Color.parse(color).get_truecolor()
    bg_hex = f"#{r:02x}{g:02x}{b:02x}"
    font_color = contrast_color_for(color)

    pill = Text(f" {title} ", style=Style(bgcolor=bg_hex, color=font_color, bold=True))
    rule_width = max(0, width - len(pill) - 1) # -1 for icons (some overflow a char and wrap the header)
    rule = Text(" " * rule_width, style="dim")
    return pill + rule
