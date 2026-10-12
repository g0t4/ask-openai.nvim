"""The clankerd daemon: primary brain that listens to voiced transcriptions."""

from __future__ import annotations

import asyncio
import json
import signal
from typing import Optional

from tools.clankerd.agent import ClankerAgent
from tools.clankerd.config import socket_path, voiced_socket_path
from tools.clankerd.logger import get_logger
from tools.clankerd.trace import TraceWriter

logger = get_logger(__name__)


class ClankerDaemon:
    """Owns the agent, the voiced client connection, and the control socket."""

    def __init__(self) -> None:
        self._trace = TraceWriter()
        self._agent = ClankerAgent(trace=self._trace)
        self._clients: set[asyncio.StreamWriter] = set()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._server: Optional[asyncio.AbstractServer] = None
        self._voiced_reader: Optional[asyncio.StreamReader] = None
        self._voiced_writer: Optional[asyncio.StreamWriter] = None
        self._voiced_task: Optional[asyncio.Task] = None
        self._current_status = "starting"
        self._active_agent_task: Optional[asyncio.Task] = None
        self._thread_id = "clankerd"
        self._shutting_down = False

    async def run(self) -> None:
        """Start the daemon; connect to voiced, serve control socket, block."""
        self._loop = asyncio.get_running_loop()

        # Install signal handlers for graceful shutdown
        for sig in (signal.SIGINT, signal.SIGTERM):
            self._loop.add_signal_handler(sig, self._shutdown)

        # Initialize the agent (MCP clients + model)
        try:
            await self._agent.setup()
            await self._set_status("ready")
            logger.info("agent initialized")
        except Exception as error:
            self._current_status = f"agent_failed: {error}"
            logger.exception("agent init failed: %s", error)

        # Connect to voiced daemon for transcriptions
        self._connect_to_voiced()

        # Start our control socket server
        await self.start_server()

        await self._set_status("idle")
        logger.info("clankerd ready; socket=%s", socket_path())

        try:
            await asyncio.Future()  # run forever
        finally:
            await self._shutdown_async()

    def _connect_to_voiced(self) -> None:
        """Best-effort connection to the voiced daemon socket."""
        if self._shutting_down:
            return
        path = voiced_socket_path()
        if not path.exists():
            logger.warning(
                "voiced socket not found at %s; retrying in 5s", path
            )
            if self._loop:
                self._loop.call_later(5.0, self._connect_to_voiced)
            return

        async def _connect():
            try:
                reader, writer = await asyncio.open_unix_connection(str(path))
                self._voiced_reader = reader
                self._voiced_writer = writer
                self._voiced_task = asyncio.create_task(self._voiced_read_loop())
                logger.info("connected to voiced at %s", path)
                await self._set_status("connected_to_voiced")
            except OSError as error:
                logger.warning("failed to connect to voiced: %s", error)
                if self._loop and not self._shutting_down:
                    self._loop.call_later(5.0, self._connect_to_voiced)

        asyncio.ensure_future(_connect())

    async def _voiced_read_loop(self) -> None:
        """Read transcription events from the voiced daemon."""
        assert self._voiced_reader is not None
        try:
            while True:
                line = await self._voiced_reader.readline()
                if not line:
                    logger.info("voiced connection closed")
                    break
                await self._handle_voiced_event(line)
        except asyncio.CancelledError:
            pass
        except Exception as error:
            logger.exception("voiced read loop error: %s", error)

    async def _handle_voiced_event(self, line: bytes) -> None:
        try:
            event = json.loads(line.decode("utf-8"))
        except json.JSONDecodeError:
            logger.warning("bad json from voiced: %r", line)
            return

        event_type = event.get("type")
        if event_type == "transcription":
            text = event.get("text", "")
            is_final = bool(event.get("final", False))
            logger.info("voiced transcription (final=%s): %s", is_final, text)

            await self._set_status("processing" if is_final else "listening")
            await self._broadcast({
                "type": "transcription",
                "text": text,
                "final": is_final,
            })

            # Send to the agent. If a final transcription arrives while a
            # live-based run is in-flight, cancel the old one so the agent can
            # re-evaluate with the definitive text.
            if is_final and self._active_agent_task and not self._active_agent_task.done():
                logger.info("cancelling in-flight agent run for final transcription")
                self._active_agent_task.cancel()
                self._trace.event(
                    "agent_cancelled",
                    reason="final_transcription_arrived",
                )

            self._active_agent_task = asyncio.create_task(
                self._run_agent(text, is_final=is_final)
            )

        elif event_type == "status":
            logger.info("voiced status: %s", event.get("state"))
            await self._broadcast({"type": "voiced_status", "state": event.get("state")})

        elif event_type == "pong":
            logger.info("voiced pong")

    async def _run_agent(self, text: str, *, is_final: bool) -> None:
        """Send a transcription to the agent and broadcast the response."""
        try:
            response = await self._agent.run(
                text,
                is_final=is_final,
                thread_id=self._thread_id,
            )
            await self._set_status("idle")
            await self._broadcast({
                "type": "agent_response",
                "text": response,
                "final": is_final,
            })
        except asyncio.CancelledError:
            logger.info("agent run cancelled")
            self._trace.event("agent_cancelled", reason="task_cancelled")
            raise
        except Exception as error:
            logger.exception("agent run failed: %s", error)
            await self._set_status("idle")
            await self._broadcast({
                "type": "error",
                "message": str(error),
            })

    async def _set_status(self, status: str) -> None:
        """Update current status and broadcast to clients."""
        self._current_status = status
        await self._broadcast({"type": "status", "state": status})

    # ----------------------------------------------------------- control socket

    async def start_server(self) -> None:
        """Start the Unix socket server (idempotent)."""
        if self._server is not None:
            return
        socket_path().parent.mkdir(parents=True, exist_ok=True)
        if socket_path().exists():
            socket_path().unlink()
        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=str(socket_path()),
        )
        logger.info("control socket server listening at %s", socket_path())

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self._clients.add(writer)
        logger.info("client connected (%d total)", len(self._clients))
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                await self._handle_command(line.decode("utf-8").strip(), writer)
        except asyncio.CancelledError:
            pass
        finally:
            self._clients.discard(writer)
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            logger.info("client disconnected (%d total)", len(self._clients))

    async def _handle_command(self, raw: str, writer: asyncio.StreamWriter) -> None:
        if not raw:
            return
        try:
            command = json.loads(raw)
        except json.JSONDecodeError:
            await self._send(writer, {"type": "error", "message": f"bad json: {raw}"})
            return

        command_type = command.get("type")
        if command_type == "ping":
            await self._send(writer, {
                "type": "pong",
                "status": self._current_status,
            })
        elif command_type == "message":
            text = command.get("text", "")
            is_final = bool(command.get("final", True))
            if is_final and self._active_agent_task and not self._active_agent_task.done():
                logger.info("cancelling in-flight agent run for manual message")
                self._active_agent_task.cancel()
            self._active_agent_task = asyncio.create_task(
                self._run_agent(text, is_final=is_final)
            )
            await self._send(writer, {"type": "ack", "message": "sent to agent"})
        elif command_type == "status":
            await self._send(writer, {"type": "status", "state": self._current_status})
        elif command_type == "shutdown":
            await self._broadcast({"type": "status", "state": "shutdown"})
            self._loop.call_soon(self._shutdown)
        else:
            await self._send(
                writer,
                {"type": "error", "message": f"unknown command: {command_type}"},
            )

    async def _send(self, writer: asyncio.StreamWriter, event: dict) -> None:
        data = json.dumps(event) + "\n"
        try:
            writer.write(data.encode("utf-8"))
            await writer.drain()
        except Exception:
            self._clients.discard(writer)

    async def _broadcast(self, event: dict) -> None:
        for writer in list(self._clients):
            await self._send(writer, event)

    def _shutdown(self) -> None:
        """Signal handler: stop the event loop."""
        self._shutting_down = True
        logger.info("shutdown signal received")
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)

    async def _shutdown_async(self) -> None:
        logger.info("shutting down")
        self._shutting_down = True
        if self._active_agent_task and not self._active_agent_task.done():
            self._active_agent_task.cancel()
            try:
                await self._active_agent_task
            except asyncio.CancelledError:
                pass
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        if self._voiced_task and not self._voiced_task.done():
            self._voiced_task.cancel()
        if self._voiced_writer:
            self._voiced_writer.close()
            try:
                await self._voiced_writer.wait_closed()
            except Exception:
                pass
