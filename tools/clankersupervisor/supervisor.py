"""The clankersupervisor daemon: manages voiced and clankerd as child processes."""

from __future__ import annotations

import asyncio
import json
import os
import signal
import subprocess
import sys
from typing import Optional

from tools.clankersupervisor.config import socket_path, pid_path
from tools.clankersupervisor.logger import get_logger

logger = get_logger(__name__)

# Path to the ask-openai.nvim repo root (where .venv lives)
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class ManagedDaemon:
    """Tracks a child daemon process."""

    def __init__(self, name: str, command: list[str], cwd: str | None = None) -> None:
        self.name = name
        self.command = command
        self.cwd = cwd
        self.proc: Optional[asyncio.subprocess.Process] = None
        self.restart_count = 0
        self.last_exit_code: int | None = None
        self.last_exit_time: float | None = None
        self.should_run = True

    async def start(self) -> None:
        """Start the child process."""
        if self.proc and not self.proc.returncode is not None:
            logger.info("%s already running (pid=%s)", self.name, self.proc.pid)
            return
        logger.info("starting %s: %s", self.name, " ".join(self.command))
        self.proc = await asyncio.create_subprocess_exec(
            *self.command,
            cwd=self.cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.restart_count += 1
        logger.info("%s started (pid=%s, restart_count=%d)", self.name, self.proc.pid, self.restart_count)

    async def stop(self) -> None:
        """Stop the child process."""
        if self.proc and self.proc.returncode is None:
            logger.info("stopping %s (pid=%s)", self.name, self.proc.pid)
            self.should_run = False
            try:
                self.proc.terminate()
                await asyncio.wait_for(self.proc.wait(), timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("%s did not stop in 5s; killing", self.name)
                self.proc.kill()
                await self.proc.wait()
            except ProcessLookupError:
                pass
        self.proc = None
        logger.info("%s stopped", self.name)

    async def restart(self) -> None:
        """Restart the child process."""
        logger.info("restarting %s", self.name)
        await self.stop()
        self.should_run = True
        await self.start()

    @property
    def is_running(self) -> bool:
        """True if the process is currently running."""
        return self.proc is not None and self.proc.returncode is None

    def status_dict(self) -> dict:
        """Return status info as a dict."""
        return {
            "name": self.name,
            "running": self.is_running,
            "pid": self.proc.pid if self.proc else None,
            "restart_count": self.restart_count,
            "last_exit_code": self.last_exit_code,
        }


class ClankerSupervisor:
    """Owns the daemon lifecycle: voiced, clankerd, and the control socket."""

    def __init__(self) -> None:
        self._clients: set[asyncio.StreamWriter] = set()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._server: Optional[asyncio.AbstractServer] = None
        self._shutting_down = False
        self._shutdown_event = asyncio.Event()

        venv_python = os.path.join(REPO_ROOT, ".venv", "bin", "python")

        self._daemons: dict[str, ManagedDaemon] = {
            "voiced": ManagedDaemon(
                name="voiced",
                command=[venv_python, "-m", "tools.voiced", "--handsfree"],
                cwd=REPO_ROOT,
            ),
            "clankerd": ManagedDaemon(
                name="clankerd",
                command=[venv_python, "-m", "tools.clankerd"],
                cwd=REPO_ROOT,
            ),
        }

    async def run(self) -> None:
        """Start all daemons and serve the control socket."""
        self._loop = asyncio.get_running_loop()

        # Install signal handlers for graceful shutdown
        for sig in (signal.SIGINT, signal.SIGTERM):
            self._loop.add_signal_handler(sig, self._request_shutdown)

        # Write PID file
        pid_path().parent.mkdir(parents=True, exist_ok=True)
        pid_path().write_text(str(os.getpid()))

        # Start all daemons
        for name, daemon in self._daemons.items():
            await daemon.start()

        # Monitor child processes for crash recovery
        monitor_task = asyncio.create_task(self._monitor_loop())

        # Start control socket server
        await self.start_server()

        logger.info("clankersupervisor ready; socket=%s", socket_path())

        try:
            await self._shutdown_event.wait()
        finally:
            monitor_task.cancel()
            try:
                await monitor_task
            except asyncio.CancelledError:
                pass
            await self._shutdown_async()

    async def _monitor_loop(self) -> None:
        """Watch child processes and auto-restart on crash."""
        while not self._shutting_down:
            for name, daemon in self._daemons.items():
                if daemon.proc and daemon.proc.returncode is not None:
                    daemon.last_exit_code = daemon.proc.returncode
                    daemon.last_exit_time = self._loop.time() if self._loop else None
                    logger.warning(
                        "%s exited with code %s; %s",
                        name,
                        daemon.proc.returncode,
                        "restarting" if daemon.should_run else "not restarting",
                    )
                    if daemon.should_run and not self._shutting_down:
                        daemon.proc = None
                        await asyncio.sleep(0.5)
                        await daemon.start()
                    else:
                        daemon.proc = None
            await asyncio.sleep(1.0)

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
        target = command.get("target", "")

        if command_type == "ping":
            await self._send(writer, {"type": "pong", "status": "running"})

        elif command_type == "status":
            statuses = {name: d.status_dict() for name, d in self._daemons.items()}
            await self._send(writer, {"type": "status", "daemons": statuses})

        elif command_type == "start":
            if target not in self._daemons:
                await self._send(writer, {"type": "error", "message": f"unknown daemon: {target}"})
                return
            daemon = self._daemons[target]
            daemon.should_run = True
            await daemon.start()
            await self._send(writer, {"type": "ack", "message": f"{target} started"})

        elif command_type == "stop":
            if target not in self._daemons:
                await self._send(writer, {"type": "error", "message": f"unknown daemon: {target}"})
                return
            daemon = self._daemons[target]
            daemon.should_run = False
            await daemon.stop()
            await self._send(writer, {"type": "ack", "message": f"{target} stopped"})

        elif command_type == "restart":
            if target not in self._daemons:
                await self._send(writer, {"type": "error", "message": f"unknown daemon: {target}"})
                return
            daemon = self._daemons[target]
            await daemon.restart()
            await self._send(writer, {"type": "ack", "message": f"{target} restarted"})

        elif command_type == "restart_all":
            for name, daemon in self._daemons.items():
                await daemon.restart()
            await self._send(writer, {"type": "ack", "message": "all daemons restarted"})

        elif command_type == "shutdown":
            await self._broadcast({"type": "status", "state": "shutdown"})
            self._request_shutdown()

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

    def _request_shutdown(self) -> None:
        """Signal handler: set the shutdown event."""
        self._shutting_down = True
        logger.info("shutdown signal received")
        if self._loop:
            self._loop.call_soon_threadsafe(self._shutdown_event.set)

    async def _shutdown_async(self) -> None:
        logger.info("shutting down")
        self._shutting_down = True
        for name, daemon in self._daemons.items():
            await daemon.stop()
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        # Remove PID file
        try:
            pid_path().unlink()
        except OSError:
            pass

