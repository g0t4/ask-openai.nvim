"""Entry point for the clankersupervisor daemon."""

from __future__ import annotations

import argparse
import asyncio

from tools.clankersupervisor.supervisor import ClankerSupervisor


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="clankersupervisor",
        description="Supervisor that manages voiced and clankerd daemons.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    supervisor = ClankerSupervisor()
    asyncio.run(supervisor.run())


if __name__ == "__main__":
    main()

