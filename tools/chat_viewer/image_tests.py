"""Multimodal tool-image messages use the existing inline image protocol."""
from copy import deepcopy
from io import StringIO

import pytest
from rich.console import Console

from tools.chat_viewer import __main__ as viewer


@pytest.mark.parametrize("role", ["user", "tool"])
def test_image_blocks_render_in_order_without_mutating_messages(role):
    blocks = [
        {"type": "text", "text": "before image"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,aGVsbG8="}},
        {"type": "text", "text": "between images"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,d29ybGQ="}},
        {"type": "text", "text": "after images"},
    ]
    messages = [
        {"role": "assistant", "tool_calls": [
            {"id": "image_call", "type": "function", "function": {
                "name": "run_bash", "arguments": '{"command": "capture"}'}}]},
        {"role": role, "content": blocks, "tool_call_id": "image_call"},
    ]
    original = deepcopy(messages)
    output = StringIO()
    viewer.render_messages_to_console(
        Console(file=output, width=120, force_terminal=True, color_system=None),
        messages[1:], context_messages=messages,
    )
    rendered = output.getvalue()
    expected = ["before image", "\x1b]1337;File=inline=1:aGVsbG8=\x07",
                "between images", "\x1b]1337;File=inline=1:d29ybGQ=\x07", "after images"]
    positions = [rendered.index(part) for part in expected]
    assert positions == sorted(positions)
    assert "data:image" not in rendered
    assert messages == original
