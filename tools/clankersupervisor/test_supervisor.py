"""Pytest tests for the clankersupervisor daemon's socket IPC protocol."""

from __future__ import annotations

import asyncio
import json

import pytest

from tools.clankersupervisor.config import socket_path
from tools.clankersupervisor.supervisor import ClankerSupervisor, ManagedDaemon


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
    supervisor = ClankerSupervisor()
    await supervisor.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"ping"}\n')
        await writer.drain()
        pong = await _read_until(reader, lambda e: e["type"] == "pong")
        assert pong["type"] == "pong"
        assert pong["status"] == "running"

        writer.close()
        await writer.wait_closed()
    finally:
        await supervisor._shutdown_async()


@pytest.mark.asyncio
async def test_status_command():
    supervisor = ClankerSupervisor()
    await supervisor.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"status"}\n')
        await writer.drain()
        status = await _read_until(reader, lambda e: e["type"] == "status")
        assert "daemons" in status
        assert "voiced" in status["daemons"]
        assert "clankerd" in status["daemons"]

        writer.close()
        await writer.wait_closed()
    finally:
        await supervisor._shutdown_async()


@pytest.mark.asyncio
async def test_unknown_daemon():
    supervisor = ClankerSupervisor()
    await supervisor.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"restart","target":"bogus"}\n')
        await writer.drain()
        error = await _read_until(reader, lambda e: e["type"] == "error")
        assert "unknown daemon" in error["message"]

        writer.close()
        await writer.wait_closed()
    finally:
        await supervisor._shutdown_async()


@pytest.mark.asyncio
async def test_unknown_command():
    supervisor = ClankerSupervisor()
    await supervisor.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        writer.write(b'{"type":"bogus"}\n')
        await writer.drain()
        error = await _read_until(reader, lambda e: e["type"] == "error")
        assert "unknown command" in error["message"]

        writer.close()
        await writer.wait_closed()
    finally:
        await supervisor._shutdown_async()


def test_managed_daemon_status_dict():
    daemon = ManagedDaemon(name="test", command=["echo", "hi"])
    status = daemon.status_dict()
    assert status["name"] == "test"
    assert status["running"] is False
    assert status["pid"] is None
    assert status["restart_count"] == 0

