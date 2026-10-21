import os
from types import SimpleNamespace

import pytest
from textual.widgets import RichLog
from tools.chat_viewer.terminal_app import TerminalSizedApp
from tools.chat_viewer.textual_viewer import TraceViewerApp


def test_real_tty_size_wins_over_stale_environment_and_updates(monkeypatch):
    monkeypatch.setenv('COLUMNS', '40')
    monkeypatch.setenv('LINES', '10')
    size = os.terminal_size((180, 55))
    monkeypatch.setattr(os, 'get_terminal_size', lambda fd: size)
    driver = TerminalSizedApp().get_driver_class()
    assert driver._get_terminal_size(SimpleNamespace()) == (180, 55)
    size = os.terminal_size((220, 70))
    assert driver._get_terminal_size(SimpleNamespace()) == (220, 70)


@pytest.mark.asyncio
async def test_existing_vtt_uses_the_full_inner_width(monkeypatch):
    from tools.chat_viewer import __main__ as viewer
    widths = []
    render = viewer.render_trace_to_console
    def capture_width(console, *args, **kwargs):
        widths.append((console.width, kwargs.get('full_width')))
        return render(console, *args, **kwargs)
    monkeypatch.setattr(viewer, 'render_trace_to_console', capture_width)
    monkeypatch.setattr(viewer, 'SHOW_ALL', False)
    monkeypatch.setattr(viewer, 'STYLE_REASONING', True)
    app = TraceViewerApp([{'role':'assistant', 'content':'OK'}])
    async with app.run_test(size=(180, 50)) as pilot:
        await pilot.pause()
        log = app.query_one(RichLog)
        assert log.region.width == 180
        assert log.region.height == 48
        assert widths[-1] == (log.scrollable_content_region.width, True)
        await pilot.resize_terminal(100, 30)
        await pilot.pause()
        assert widths[-1] == (log.scrollable_content_region.width, True)
