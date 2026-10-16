"""Live bridge: reads clankerd's control socket, serves events to a browser over WebSocket.

Usage:  .venv/bin/python wip/clinker-dashboard/bridge.py  [--port 8765]
"""
from __future__ import annotations

import asyncio
import functools
print = functools.partial(print, flush=True)
import json
import socket
import sys
import threading
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.clankerd.config import socket_path as clankerd_socket


class Bridge:
    def __init__(self, port: int = 8765):
        self.port = port
        self.clients: set = set()
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.reconnect_task: asyncio.Task | None = None

    # ---- clankerd socket connection ----
    async def _connect_clankerd(self):
        path = clankerd_socket()
        if not path.exists():
            print(f"[bridge] waiting for clankerd socket at {path} ...")
            await asyncio.sleep(2)
            return
        try:
            self.reader, self.writer = await asyncio.open_unix_connection(str(path))
            print(f"[bridge] connected to clankerd at {path}")
            await self._broadcast({"type": "system", "message": "connected to clankerd"})
            while True:
                line = await self.reader.readline()
                if not line:
                    print("[bridge] clankerd closed connection")
                    break
                await self._forward(line.decode("utf-8").strip())
        except OSError as e:
            print(f"[bridge] clankerd error: {e}")
        finally:
            if self.writer:
                self.writer.close()
                try:
                    await self.writer.wait_closed()
                except Exception:
                    pass
            self.reader = None
            self.writer = None
            await asyncio.sleep(2)

    async def _forward(self, raw: str):
        if not raw:
            return
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            return
        print(f"[bridge] <- {raw}")
        await self._broadcast(event)

    async def _reconnect_loop(self):
        while True:
            if not self.writer:
                await self._connect_clankerd()
            await asyncio.sleep(2)

    # ---- websocket server ----
    async def _handler(self, ws):
        self.clients.add(ws)
        print(f"[bridge] browser connected ({len(self.clients)} total)")
        try:
            # send current status on connect
            await ws.send(json.dumps({"type": "system", "message": "connected"}))
            async for message in ws:
                pass
        except Exception:
            pass
        finally:
            self.clients.discard(ws)
            print(f"[bridge] browser disconnected ({len(self.clients)} total)")

    async def _broadcast(self, event: dict):
        if not self.clients:
            return
        data = json.dumps(event)
        dead = []
        for ws in self.clients:
            try:
                await ws.send(data)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)

    async def run(self):
        async with websockets.serve(self._handler, "127.0.0.1", self.port):
            print(f"[bridge] websocket server on ws://127.0.0.1:{self.port}")
            await self._connect_clankerd()
            await self._reconnect_loop()


if __name__ == "__main__":
    port = 8766
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    try:
        asyncio.run(Bridge(port).run())
    except KeyboardInterrupt:
        pass
