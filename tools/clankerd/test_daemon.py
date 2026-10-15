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
