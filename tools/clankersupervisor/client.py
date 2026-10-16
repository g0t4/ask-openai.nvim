"""CLI client for the clankersupervisor daemon."""

from __future__ import annotations

import argparse
import asyncio
import json

from tools.clankersupervisor.config import socket_path


async def send_command(command: dict, timeout: float = 10.0) -> dict | None:
    """Send a command to the supervisor and read the response."""
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))
    except OSError as error:
        print(f"ERROR: Cannot connect to supervisor at {socket_path()}: {error}")
        return None

    writer.write((json.dumps(command) + "\n").encode())
    await writer.drain()

    line = await asyncio.wait_for(reader.readline(), timeout=timeout)
    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass

    if not line:
        return None
    return json.loads(line.decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="clankersupervisor-client",
        description="Control the ask-openai daemon supervisor.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="Show status of all daemons")
    subparsers.add_parser("ping", help="Ping the supervisor")

    for name in ("voiced", "clankerd"):
        sub = subparsers.add_parser(f"start-{name}", help=f"Start {name}")
        sub = subparsers.add_parser(f"stop-{name}", help=f"Stop {name}")
        sub = subparsers.add_parser(f"restart-{name}", help=f"Restart {name}")

    subparsers.add_parser("restart-all", help="Restart all daemons")
    subparsers.add_parser("shutdown", help="Shutdown the supervisor")

    args = parser.parse_args()

    cmd = args.command
    if cmd == "status":
        response = asyncio.run(send_command({"type": "status"}))
    elif cmd == "ping":
        response = asyncio.run(send_command({"type": "ping"}))
    elif cmd.startswith("start-"):
        response = asyncio.run(send_command({"type": "start", "target": cmd[6:]}))
    elif cmd.startswith("stop-"):
        response = asyncio.run(send_command({"type": "stop", "target": cmd[5:]}))
    elif cmd.startswith("restart-"):
        response = asyncio.run(send_command({"type": "restart", "target": cmd[8:]}))
    elif cmd == "restart-all":
        response = asyncio.run(send_command({"type": "restart_all"}))
    elif cmd == "shutdown":
        response = asyncio.run(send_command({"type": "shutdown"}))
    else:
        response = None

    if response:
        print(json.dumps(response, indent=2))


if __name__ == "__main__":
    main()

