"""Socket framing, reconnects, partial rendering, and live/disk reconciliation."""
import asyncio
import io
import json
import os
import shutil
import time
import tempfile
from pathlib import Path

import pytest
from rich.console import Console

from tools.chat_viewer import __main__ as viewer
from tools.chat_viewer.live_stream import StreamState, TraceSocketSubscriber
from tools.chat_viewer.live_viewer import LiveTraceViewerApp


@pytest.fixture
def socket_directory():
    # macOS socket paths must fit within 104 bytes.
    with tempfile.TemporaryDirectory(prefix="ask-stream-", dir="/tmp") as directory:
        yield Path(directory)


def event(path, messages, *, prefix=0, sequence=1, status="streaming", updated_at=None):
    return {"version": 1, "type": "snapshot", "trace_path": str(path), "messages": messages,
            "replace_from": prefix, "sequence": sequence, "status": status,
            "model_name": "actual-model", "updated_at": updated_at or time.time()}


def test_stream_suffix_replaces_partial_and_rejects_invalid_bases(tmp_path):
    state = StreamState()
    path = tmp_path / '1-trace.json'
    user = {"role": "user", "content": "hello"}
    partial = {"role": "assistant", "content": "partial", "_partial": True}
    state.apply(event(path, [user, partial]))
    final = {"role": "assistant", "content": "complete", "usage": {"completion_tokens": 7}}
    result = state.apply(event(path, [final], prefix=1, sequence=2, status="idle"))
    assert result.messages == [user, final]
    assert result.messages[0] is user
    assert not result.messages[1].get('_partial')
    with pytest.raises(ValueError):
        state.apply(event(tmp_path / 'other-trace.json', [], prefix=1, sequence=3))
    with pytest.raises(ValueError):
        state.apply(event(path, [], prefix=99, sequence=3))
    with pytest.raises(ValueError):
        state.apply(event(path, [], sequence=1))
    assert state.apply(event(tmp_path / 'other-trace.json', [], sequence=3)).messages == []


def test_partial_renderer_shows_literal_reasoning_content_and_broken_tool_json():
    message = {"role": "assistant", "_partial": True,
               "reasoning_content": "[bold]reasoning[/bold] **unfinished",
               "content": "[red]literal[/red] ```python",
               "tool_calls": [{"type": "function", "function": {
                   "name": "run_bash", "arguments": '{"command_line":"echo [blue]'}}]}
    output = io.StringIO()
    viewer.render_messages_to_console(Console(file=output, width=120, color_system=None), [message], full_width=True)
    text = output.getvalue()
    assert 'ASSISTANT' in text
    assert '[bold]reasoning[/bold] **unfinished' in text
    assert '[red]literal[/red] ```python' in text
    assert '{"command_line":"echo [blue]' in text
    assert text.index('reasoning[/bold]') < text.index('literal[/red]') < text.index('run_bash')
    assert 'Unable to render' not in text
    # A tool-call header with no function/arguments yet is valid partial state.
    viewer.render_messages_to_console(Console(file=io.StringIO()), [{"role":"assistant", "_partial":True,
                                                                   "tool_calls":[{}]}])


@pytest.mark.asyncio
async def test_subscriber_handles_fragmented_frames_and_reconnects(socket_directory):
    tmp_path = socket_directory
    socket = tmp_path / 'live-test.sock'
    snapshots = []
    disconnects = []
    connected = 0
    async def serve(reader, writer):
        nonlocal connected
        connected += 1
        frame = json.dumps(event(tmp_path / '1-trace.json', [{"role":"assistant", "content":f"connection {connected}"}])).encode() + b'\n'
        writer.write(frame[:15])
        await writer.drain()
        await asyncio.sleep(0.01)
        writer.write(frame[15:])
        await writer.drain()
        writer.close()
        await writer.wait_closed()
    server = await asyncio.start_unix_server(serve, path=socket)
    subscriber = TraceSocketSubscriber(tmp_path, lambda source, snapshot: snapshots.append(snapshot),
                                       disconnects.append, retry_interval=0.02)
    task = asyncio.create_task(subscriber.run())
    try:
        for _ in range(100):
            await asyncio.sleep(0.02)
            if len(snapshots) >= 2:
                break
        assert len(snapshots) >= 2
        assert snapshots[0].messages[0]['content'] == 'connection 1'
        assert snapshots[1].messages[0]['content'] == 'connection 2'
        assert disconnects
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        server.close()
        await server.wait_closed()
    assert not subscriber.connections


@pytest.mark.asyncio
async def test_tui_prefers_live_over_same_trace_disk_and_recovers_after_disconnect(tmp_path):
    path = tmp_path / '1-trace.json'
    user = {"role":"user", "content":"hello"}
    path.write_text(json.dumps({"request_body":{"messages":[user]}}))
    app = LiveTraceViewerApp(tmp_path, poll_interval=3600)
    source = tmp_path / 'live-test.sock'
    state = StreamState()
    async with app.run_test(size=(100, 30)) as pilot:
        original_user = app.query_one('#message-0')
        stream = state.apply(event(path, [user, {"role":"assistant", "content":"live [", "_partial":True}]))
        app._receive_stream(source, stream)
        await app.poll_stream()
        assert app.query_one('#message-0') is original_user
        assert app.snapshot.messages[-1]['_partial']
        # A disk save from the previous turn must not erase streaming tokens.
        path.write_text(json.dumps({"request_body":{"messages":[user]}}))
        await app.poll_directory()
        assert app.snapshot.messages[-1]['content'] == 'live ['
        final = {"role":"assistant", "content":"complete", "usage":{"completion_tokens":7}}
        app._receive_stream(source, state.apply(event(path, [final], prefix=1, sequence=2, status="idle")))
        await app.poll_stream()
        assert app.snapshot.messages == [user, final]
        assert app.query_one('#message-0') is original_user
        path.write_text(json.dumps({"request_body":{"messages":[user, final]}}))
        app._disconnect_stream(source)
        await app.poll_directory()
        assert app.snapshot.messages == [user, final]
        assert app._displayed_source is None
        # An older idle publisher must not steal focus from the newer trace.
        app._receive_stream(source, state.apply(event(path, [], sequence=3, updated_at=1)))
        await app.poll_stream()
        assert app.snapshot.messages == [user, final]
        await pilot.pause()


@pytest.mark.asyncio
@pytest.mark.skipif(shutil.which('nvim') is None, reason='Neovim is required for the cross-language smoke test')
async def test_real_neovim_socket_streams_into_textual(tmp_path):
    # macOS Unix socket paths have a small limit; pytest directories can exceed it.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='ask-live-', dir='/tmp') as directory:
        directory = Path(directory)
        socket = directory / 'live-nvim.sock'
        script = directory / 'publisher.lua'
        repo = Path(__file__).resolve().parents[2]
        script.write_text('''
vim.opt.runtimepath:append(vim.env.ASK_LIVE_TEST_REPO)
local Publisher = require("ask-openai.agents.live_trace_stream").Publisher
local publisher = Publisher.new(vim.env.ASK_LIVE_TEST_SOCKET, 5)
assert(publisher:start())
local trace = { start_time = 123, messages = { { role = "user", content = "hello from Neovim" } } }
local request = { body = { model = "test-model" }, accumulated_model_response_messages = {} }
publisher:begin_request(trace, request)
assert(vim.wait(5000, function() return next(publisher.clients) ~= nil end, 10))
request.accumulated_model_response_messages[1] = { reasoning_content = "thinking [", content = "live tokens [" }
publisher:changed(trace)
vim.defer_fn(function()
    trace.messages[2] = { role = "assistant", content = "finished Neovim response", usage = { completion_tokens = 4 } }
    publisher:finish_request(trace)
end, 600)
vim.wait(2000, function() return false end, 10)
publisher:close()
vim.cmd("qa!")
''')
        process = await asyncio.create_subprocess_exec('nvim', '-u', 'NONE', '-i', 'NONE', '--headless', '-l', str(script),
            env={**os.environ, 'ASK_LIVE_TEST_REPO':str(repo), 'ASK_LIVE_TEST_SOCKET':str(socket)},
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        app = LiveTraceViewerApp(directory, poll_interval=0.05)
        try:
            async with app.run_test(size=(100, 30)) as pilot:
                for _ in range(60):
                    await pilot.pause(0.03)
                    if app.snapshot and app.snapshot.messages[-1].get('_partial'):
                        break
                assert app.snapshot.messages[-1]['content'] == 'live tokens ['
                assert app.snapshot.messages[-1]['reasoning_content'] == 'thinking ['
                for _ in range(60):
                    await pilot.pause(0.03)
                    if app.snapshot.messages[-1].get('usage'):
                        break
                assert len(app.snapshot.messages) == 2
                assert app.snapshot.messages[-1]['content'] == 'finished Neovim response'
                assert app.snapshot.messages[-1]['usage']['completion_tokens'] == 4
                assert not app.snapshot.messages[-1].get('_partial')
            _, errors = await asyncio.wait_for(process.communicate(), timeout=5)
            assert process.returncode == 0, errors.decode()
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()
