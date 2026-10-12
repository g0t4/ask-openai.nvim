"""Entry point for the clankerd daemon: ``python -m tools.clankerd``."""

from __future__ import annotations

import argparse
import asyncio

from tools.clankerd.daemon import ClankerDaemon


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="clankerd",
        description="Primary brain daemon that listens to voiced transcriptions.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    daemon = ClankerDaemon()
    asyncio.run(daemon.run())


if __name__ == "__main__":
    main()
