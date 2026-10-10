"""Entry point for the voiced daemon: ``python -m tools.voiced``."""

from __future__ import annotations

import argparse
import asyncio

from tools.voiced.config import DEFAULT_MODEL_PATH
from tools.voiced.daemon import VoicedDaemon


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="voiced",
        description="Push-to-talk speech-to-text daemon (whisper.cpp).",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL_PATH,
        help="path to a whisper.cpp ggml model file",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=4,
        help="number of whisper.cpp inference threads",
    )
    parser.add_argument(
        "--step-ms",
        type=int,
        default=1500,
        help="how often (ms) to transcribe while listening",
    )
    parser.add_argument(
        "--max-length-ms",
        type=int,
        default=30000,
        help="max audio (ms) to feed each transcription",
    )
    parser.add_argument(
        "--device",
        type=int,
        default=None,
        help="input device index (default: system default)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    daemon = VoicedDaemon(
        model_path=args.model,
        n_threads=args.threads,
        step_ms=args.step_ms,
        max_length_ms=args.max_length_ms,
        device=args.device,
    )
    asyncio.run(daemon.run())


if __name__ == "__main__":
    main()

