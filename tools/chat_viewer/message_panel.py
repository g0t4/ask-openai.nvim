from typing import Literal

from rich.align import Align
from rich.console import Console
from rich.measure import measure_renderables
from rich.panel import Panel

from tools.chat_viewer.tree_wrapper import TreeWrapper

# # Chat-style panel boxes: only a top border plus the border on the aligned edge,
# # so messages read as open speech bubbles flowing toward the aligned side.
# # User (right-aligned) -> top + right border.
# CHAT_BOX_RIGHT = box.Box(
#     " ──╮\n"
#     "   │\n"
#     "   │\n"
#     "   │\n"
#     "   │\n"
#     "   │\n"
#     "   │\n"
#     "    "
# )
# # Assistant (left-aligned) -> top + left border.
# CHAT_BOX_LEFT = box.Box(
#     "╭── \n"
#     "│   \n"
#     "│   \n"
#     "│   \n"
#     "│   \n"
#     "│   \n"
#     "│   \n"
#     "    "
# )


def print_message_panel(
    title: str,
    color: str,
    content: TreeWrapper,
    align: Literal['left']|Literal['right']|Literal['center'],
    _console: Console,
    *,
    full_width: bool = False,
    min_panel_width: int = 50,
) -> None:
    """Render a single message as an aligned panel for a chat-like layout.

    User messages are right-aligned, everything else left-aligned. The panel is
    capped at a readable width so short messages read as bubbles instead of
    spanning the full terminal width.
    """
    available_width = max(1, int(_console.width * 0.9 + 0.5))
    if full_width:
        # Full width: panel spans nearly the whole terminal (90%).
        max_panel_width = available_width
    else:
        # Bubble mode: cap at a readable width (100 cols max), leaving a small
        # margin from the terminal edge, but never shrink below 20 cols.
        max_bubble_width = min(_console.width - 4, 100)
        max_bubble_width = max(40, max_bubble_width)
        # Also don't let the bubble exceed the 90% available width.
        max_panel_width = min(available_width, max_bubble_width)

    # Open speech-bubble look: keep the border on the side the message hugs.
    # chat_box = CHAT_BOX_RIGHT if align == "right" else CHAT_BOX_LEFT
    panel_padding = (1, 2)
    # The panel wraps content in padding + a border, so the content needs that
    # extra horizontal room (both sides + left/right border) to avoid wrapping.
    panel_overhead = panel_padding[1] * 2 + 2
    if min_panel_width:
        # Measure the content's natural width so a tiny result still gets a
        # minimum-width bubble instead of collapsing to the title's width.
        content_width = measure_renderables(_console, _console.options, [content]).maximum
        panel_width = min(max_panel_width, max(min_panel_width, content_width + panel_overhead))
        expand = True
    else:
        panel_width = max_panel_width
        expand = False

    panel = Panel(
        content,
        title=f"[{color}]{title}[/]",
        title_align="right" if align == "right" else "left",
        border_style=color,
        padding=panel_padding,
        width=panel_width,
        expand=expand,
        # box=chat_box, # comment out to go back to border around all sides
        # btw short width tool results are where I really like seeing panel with full border... don't get rid of chat_box yet though, keep it around to use again
    )

    _console.print(Align(panel, align=align))
    _console.print()  # blank line between messages
