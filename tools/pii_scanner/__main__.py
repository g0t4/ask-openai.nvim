"""CLI entry point for the PII scanner.

Usage:
    python -m tools.pii_scanner [OPTIONS] [TARGET_DIR]

Examples:
    python -m tools.pii_scanner                              # regex mode (default)
    python -m tools.pii_scanner ./data                       # scan specific directory
    python -m tools.pii_scanner --threshold 0.8              # higher confidence
    python -m tools.pii_scanner --model openai/privacy-filter  # transformers mode
    python -m tools.pii_scanner --json                       # JSON output
"""

import argparse
import json as json_module
import sys
from pathlib import Path

from rich.console import Console

from tools.pii_scanner.scanner import (
    PII_CATEGORIES,
    run_scan,
    print_summary,
    print_file_results,
)

_console = Console(color_system="truecolor")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Scan JSON files in a directory for PII.",
        epilog=f"PII categories: {', '.join(PII_CATEGORIES)}",
    )
    parser.add_argument(
        "target_dir",
        nargs="?",
        default=".",
        help="Directory to scan for JSON files (default: current directory)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "HuggingFace model name for transformers-based detection. "
            "If omitted, uses regex-based detection (no model download needed)."
        ),
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="Minimum confidence score to report a finding (default: 0.5)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON to stdout",
    )
    return parser.parse_args(argv)


def output_json(results: list, mode: str) -> None:
    """Output scan results as JSON to stdout."""
    output = []
    for result in results:
        entry = {"file": str(result.file_path), "mode": mode, "findings": []}
        if result.error:
            entry["error"] = result.error
        else:
            for finding in result.findings:
                entry["findings"].append({
                    "category": finding.entity_group,
                    "text": finding.text,
                    "start": finding.start_char,
                    "end": finding.end_char,
                    "score": finding.score,
                })
        output.append(entry)
    _console.print(json_module.dumps(output, indent=2))


def main(argv: list[str] | None = None) -> None:
    """Main entry point."""
    args = parse_args(argv)

    target_path = Path(args.target_dir).resolve()
    if not target_path.is_dir():
        _console.print(f"[red]Error: {target_path} is not a directory.[/]")
        sys.exit(1)

    results, mode = run_scan(
        target_dir=target_path,
        model_name=args.model,
        scoring_threshold=args.threshold,
    )

    if args.json:
        output_json(results, mode)
    else:
        for result in results:
            print_file_results(result, mode)
        print_summary(results, mode)


if __name__ == "__main__":
    main()
