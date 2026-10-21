"""Live watcher and real Textual widget update regressions."""
import json
import os
from io import StringIO
from pathlib import Path

import pytest
from rich.console import Console
from textual.containers import VerticalScroll
from tools.chat_viewer import __main__ as viewer
from tools.chat_viewer.live_viewer import LiveTraceViewerApp, TraceDirectoryWatcher, TraceSnapshot


def save(path, messages, timestamp):
    path.write_text(json.dumps({"request_body": {"messages": messages},
                                "last_sse": {"model": "deepseek-v4.1-flash"}}))
    os.utime(path, ns=(timestamp, timestamp))


def test_watcher_uses_last_save_not_filename_and_retries_partial_writes(tmp_path):
    watcher = TraceDirectoryWatcher(tmp_path)
    assert watcher.poll() is None
    old = tmp_path / '999-trace.json'
    new = tmp_path / '100-trace.json'
    messages = [{"role": "user", "content": "hello"}]
    save(old, messages, 1000)
    save(new, messages, 2000)
    assert watcher.poll().path == new
    assert watcher.poll() is None
    save(old, messages, 3000)
    assert watcher.poll().path == old
    new.write_text('{"request_body":')
    os.utime(new, ns=(4000, 4000))
    assert watcher.poll() is None
    assert watcher.error
    # Valid completion with the same mtime is still retried (not marked loaded).
    save(new, messages, 4000)
    assert watcher.poll().path == new
    assert watcher.error is None
    (tmp_path / 'not-a-trace.json.bak').write_text('{}')
    assert watcher.poll() is None


def test_partial_message_renderer_resolves_tool_from_full_history():
    history = [
        {"role": "assistant", "tool_calls": [{"id": "call", "type": "function",
         "function": {"name": "run_bash", "arguments": '{"command_line":"date"}'}}]},
        {"role": "tool", "tool_call_id": "call", "content": "STDOUT: hello"},
    ]
    output = StringIO()
    original_console = viewer._console
    viewer.render_messages_to_console(Console(file=output, width=100), history[1:], start_index=2,
                                      context_messages=history)
    assert "2:" in output.getvalue()
    assert "STDOUT: hello" in output.getvalue()
    assert viewer._console is original_console


@pytest.mark.asyncio
async def test_live_updates_reuse_prefix_replace_suffix_switch_and_follow(tmp_path, monkeypatch):
    monkeypatch.setattr(viewer, "SHOW_ALL", False)
    app = LiveTraceViewerApp(tmp_path, poll_interval=3600)
    first = tmp_path / 'one-trace.json'
    second = tmp_path / 'two-trace.json'
    user = {"role": "user", "content": "hello\n" * 30}
    assistant = {"role": "assistant", "content": "first answer\n" * 30,
                 "usage": {"prompt_tokens": 6, "completion_tokens": 2},
                 "metrics": {"tokens_per_second": 11.7}}
    async with app.run_test(size=(100, 24)) as pilot:
        save(first, [user, assistant], 1000)
        await app.poll_directory()
        await pilot.pause()
        transcript = app.query_one('#transcript', VerticalScroll)
        original_user = app.query_one('#message-0')
        original_assistant = app.query_one('#message-1')
        assert transcript.scroll_y > 0
        assert transcript.is_vertical_scroll_end
        save(first, [user, assistant, {"role":"user", "content":"next question"}], 2000)
        await app.poll_directory()
        await pilot.pause()
        assert app.query_one('#message-0') is original_user
        assert app.query_one('#message-1') is original_assistant
        changed = {**assistant, "content": "updated answer"}
        save(first, [user, changed], 3000)
        await app.poll_directory()
        await pilot.pause()
        assert app.query_one('#message-0') is original_user
        assert app.query_one('#message-1') is not original_assistant
        assert len(transcript.children) == 2
        await pilot.press('f')
        transcript.scroll_home(animate=False)
        await pilot.pause()
        save(first, [user, assistant], 4000)
        await app.poll_directory()
        await pilot.pause()
        assert transcript.scroll_y == 0
        assert not app.follow_latest
        await pilot.press('f')
        await pilot.pause()
        assert transcript.is_vertical_scroll_end
        # A different trace replaces everything, even an identical prefix.
        save(second, [user], 5000)
        await app.poll_directory()
        await pilot.pause()
        assert app.snapshot.path == second
        assert app.query_one('#message-0') is not original_user
        assert len(transcript.children) == 1
        # A partial save leaves the displayed message widgets untouched.
        stable = app.query_one('#message-0')
        second.write_text('{')
        await app.poll_directory()
        assert app.query_one('#message-0') is stable
        await pilot.press('a', 'r')
        await pilot.pause()
        assert app.snapshot.path == second


@pytest.mark.asyncio
async def test_startup_and_timer_automatically_follow_new_saves(tmp_path):
    first = tmp_path / 'first-trace.json'
    save(first, [{"role": "assistant", "content": "initial answer"}], 1000)
    app = LiveTraceViewerApp(tmp_path, poll_interval=0.05)
    async with app.run_test(size=(80, 24)) as pilot:
        assert app.snapshot.path == first
        unchanged_widget = app.query_one('#message-0')
        save(first, [{"role":"assistant", "content":"initial answer"},
                     {"role":"assistant", "content":"timer update"}], 2000)
        for _ in range(20):
            await pilot.pause(0.05)
            if len(app.snapshot.messages) == 2:
                break
        assert len(app.snapshot.messages) == 2
        assert app.query_one('#message-0') is unchanged_widget
        second = tmp_path / 'new-session-trace.json'
        save(second, [{"role":"assistant", "content":"new session"}], 3000)
        for _ in range(20):
            await pilot.pause(0.05)
            if app.snapshot.path == second:
                break
        assert app.snapshot.path == second
        assert len(app.query_one('#transcript').children) == 1


def test_live_renderer_can_fill_a_wide_terminal_without_changing_cli_bubbles():
    message = {"role": "assistant", "content": "wide content " * 80}
    output = StringIO()
    viewer.render_messages_to_console(Console(file=output, width=180), [message], full_width=True)
    assert max(len(line.rstrip()) for line in output.getvalue().splitlines()) > 150
    output = StringIO()
    viewer.render_messages_to_console(Console(file=output, width=180), [message])
    assert max(len(line.rstrip()) for line in output.getvalue().splitlines()) <= 100


@pytest.mark.asyncio
async def test_live_transcript_fills_terminal_and_reflows_after_resize(tmp_path, monkeypatch):
    save(tmp_path / 'wide-trace.json', [{"role":"assistant", "content":"long message " * 1000}], 1000)
    widths = []
    original_render = viewer.render_messages_to_console
    def capture_width(console, *args, **kwargs):
        widths.append(console.width)
        return original_render(console, *args, **kwargs)
    monkeypatch.setattr(viewer, 'render_messages_to_console', capture_width)
    app = LiveTraceViewerApp(tmp_path, poll_interval=3600)
    async with app.run_test(size=(160, 50)) as pilot:
        await pilot.pause()
        transcript = app.query_one('#transcript', VerticalScroll)
        assert transcript.region.width == 160
        assert transcript.region.height == 48  # one header and one footer row
        assert widths[-1] == transcript.scrollable_content_region.width
        assert widths[-1] > 100
        await pilot.resize_terminal(220, 60)
        await pilot.pause()
        assert transcript.region.width == 220
        assert transcript.region.height == 58
        assert widths[-1] == transcript.scrollable_content_region.width
        await pilot.resize_terminal(60, 20)
        await pilot.pause()
        assert transcript.region.width == 60
        assert transcript.region.height == 18
        assert widths[-1] == transcript.scrollable_content_region.width
