"""Pytest tests for the clankerd daemon's socket IPC protocol."""

from __future__ import annotations

import asyncio
import json

import pytest

from tools.clankerd.config import socket_path
from tools.clankerd.daemon import ClankerDaemon


class FakeAgent:
    """Duck-typed stand-in for ClankerAgent that returns a fixed response."""

    async def setup(self) -> None:
        pass

    async def shutdown(self) -> None:
        pass

    async def run(
        self,
        user_message: str,
        *,
        is_final: bool,
        thread_id: str | None = None,
        recursion_limit: int = 50,
    ) -> str:
        return f"processed: {user_message}"


async def _read_until(
    reader: asyncio.StreamReader, predicate, timeout: float = 5.0
) -> dict:
    async def _pump():
        while True:
            line = await reader.readline()
            if not line:
                raise asyncio.TimeoutError("stream closed")
            event = json.loads(line.decode("utf-8"))
            if predicate(event):
                return event

    return await asyncio.wait_for(_pump(), timeout=timeout)


@pytest.mark.asyncio
async def test_ping_pong():
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"ping"}\n')
        await writer.drain()
        pong = await _read_until(reader, lambda e: e["type"] == "pong")
        assert pong["type"] == "pong"
        assert "status" in pong

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_message_command():
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"message","text":"hello clankerd","final":true}\n')
        await writer.drain()

        ack = await _read_until(reader, lambda e: e["type"] == "ack")
        assert ack["message"] == "sent to agent"

        # Wait for the agent response broadcast
        response = await _read_until(
            reader, lambda e: e["type"] == "agent_response"
        )
        assert response["text"] == "processed: hello clankerd"
        assert response["final"] is True

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_status_command():
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"status"}\n')
        await writer.drain()
        status = await _read_until(reader, lambda e: e["type"] == "status")
        assert "state" in status

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_unknown_command():
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"bogus"}\n')
        await writer.drain()
        error = await _read_until(reader, lambda e: e["type"] == "error")
        assert "unknown command" in error["message"]

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_final_transcription_triggers_agent_run():
    """Final transcriptions should always trigger an agent run."""
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    try:
        await daemon._handle_final_transcription("Can you explain 6-7?")

        # Wait for the agent run to complete
        if daemon._active_agent_task:
            await daemon._active_agent_task
        assert daemon._active_agent_task.done()
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_live_transcription_does_not_trigger_agent_run():
    """Live transcriptions should never trigger agent runs (final-only model)."""
    daemon = ClankerDaemon()
    daemon._agent = FakeAgent()
    try:
        # Send a live transcription through the voiced event handler
        await daemon._handle_voiced_event(
            b'{"type":"transcription","text":"Tell me something funny","final":false}\n'
        )

        # Agent should NOT be running
        assert daemon._active_agent_task is None, (
            "Live transcriptions must not trigger agent runs"
        )
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_final_queues_when_agent_busy():
    """A new final transcription should be queued while agent is busy."""
    daemon = ClankerDaemon()

    class BlockingAgent(FakeAgent):
        """Agent that blocks on the first run, then completes on second."""

        async def run(self, user_message, *, is_final, thread_id=None, recursion_limit=50):
            if user_message == "first":
                # Block until cancelled
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    raise
            return f"processed: {user_message}"

    daemon._agent = BlockingAgent()
    try:
        # Start a run that blocks
        await daemon._handle_final_transcription("first")
        assert daemon._active_agent_task is not None
        assert not daemon._active_agent_task.done()

        # Now a new final arrives while agent is busy - should be queued
        await daemon._handle_final_transcription("second")
        assert len(daemon._queued_final_transcriptions) == 1
        assert daemon._queued_final_transcriptions[0] == "second"

        # The original run should still be in-flight (not cancelled)
        assert daemon._active_agent_task is not None
        assert not daemon._active_agent_task.done()

        # Cancel the blocking run to clean up
        daemon._active_agent_task.cancel()
        try:
            await daemon._active_agent_task
        except asyncio.CancelledError:
            pass
    finally:
        await daemon._shutdown_async()


@pytest.mark.asyncio
async def test_queued_finals_delivered_after_run_completes():
    """Queued finals should be delivered after the current run completes."""
    daemon = ClankerDaemon()

    class SlowAgent(FakeAgent):
        """Agent that takes a moment to complete."""

        async def run(self, user_message, *, is_final, thread_id=None, recursion_limit=50):
            await asyncio.sleep(0.1)
            return f"processed: {user_message}"

    daemon._agent = SlowAgent()
    try:
        # Start a run that takes a moment
        await daemon._handle_final_transcription("first")
        assert daemon._active_agent_task is not None
        assert not daemon._active_agent_task.done()

        # Queue a follow-up while agent is busy
        await daemon._handle_final_transcription("follow up")
        assert len(daemon._queued_final_transcriptions) == 1

        # Wait for the first run to complete (which should trigger queue drain)
        await asyncio.wait_for(daemon._active_agent_task, timeout=5.0)
        assert daemon._active_agent_task.done()

        # The queued follow-up should have been processed
        assert len(daemon._queued_final_transcriptions) == 0
    finally:
        await daemon._shutdown_async()
