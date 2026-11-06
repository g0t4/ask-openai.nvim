"""CLI entry point for summarizing a video with a vision model.

Usage:
    python -m tools.summarize_video video.mp4
    python -m tools.summarize_video --width 320 --fps 1 video.mp4
"""

import argparse
import sys
from pathlib import Path

from tools.summarize_video.summarize import (
    DEFAULT_BASE_URL,
    DEFAULT_FPS,
    DEFAULT_MAX_FRAMES,
    DEFAULT_MAX_TOKENS,
    DEFAULT_MODEL,
    DEFAULT_PROMPT,
    DEFAULT_TEMPERATURE,
    DEFAULT_WIDTH,
    summarize_video,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Summarize a video with a vision model via llama-server.",
    )
    parser.add_argument("video", help="Path to the video file to summarize")
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help="llama-server base URL (default: %(default)s)",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="Model id (default: auto-detect from /v1/models)",
    )
    parser.add_argument("--prompt", default=DEFAULT_PROMPT, help="Prompt guiding the summary")
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=DEFAULT_MAX_TOKENS,
        help="Maximum output tokens (default: %(default)s)",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=DEFAULT_WIDTH,
        help="Downscale width before sending (default: %(default)s)",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=DEFAULT_FPS,
        help="Target frames per second (default: %(default)s)",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=DEFAULT_MAX_FRAMES,
        help="Maximum number of frames sent to the model (default: %(default)s)",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=DEFAULT_TEMPERATURE,
        help="Sampling temperature (default: %(default)s)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    """Run the CLI and write the summary to stdout."""
    args = parse_args(argv)
    result = summarize_video(
        Path(args.video),
        base_url=args.base_url,
        model=args.model,
        prompt=args.prompt,
        max_tokens=args.max_tokens,
        width=args.width,
        fps=args.fps,
        max_frames=args.max_frames,
        temperature=args.temperature,
    )
    print(result)


if __name__ == "__main__":
    main(sys.argv[1:])

