"""CLI entry point for the PII scanner.

Usage:
    python -m tools.pii_scanner [OPTIONS] [TARGET]

Examples:
    python -m tools.pii_scanner                              # regex mode (default)
    python -m tools.pii_scanner ./data                       # scan specific directory
    python -m tools.pii_scanner file.json                    # scan single file
    python -m tools.pii_scanner --threshold 0.8              # higher confidence
    python -m tools.pii_scanner --model openai/privacy-filter  # transformers mode
    python -m tools.pii_scanner --json                       # JSON output
    python -m tools.pii_scanner --show-matches               # display actual PII text
    python -m tools.pii_scanner --extract-paths              # extract file paths from trace files
    python -m tools.pii_scanner --extract-paths trace.json   # extract from single file
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
    run_extract_paths,
    print_extract_paths_results,
    extract_paths_from_trace,
)

_console = Console(color_system="truecolor")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Scan JSON files for PII, or extract file paths from trace files.",
        epilog=f"PII categories: {', '.join(PII_CATEGORIES)}",
    )
    parser.add_argument(
        "target",
        nargs="?",
        default=".",
        help="Directory or single JSON file to scan (default: current directory)",
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
    parser.add_argument(
        "--show-matches",
        action="store_true",
        help="Display actual PII text instead of masked dots (use with caution)",
    )
    parser.add_argument(
        "--extract-paths",
        action="store_true",
        help="Extract file paths from *-trace.json files (skips PII scanning)",
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

    target_path = Path(args.target).resolve()

    # ── Single file mode ──
    if target_path.is_file():
        if not target_path.suffix == ".json":
            _console.print(f"[red]Error: {target_path} is not a JSON file.[/]")
            sys.exit(1)

        if args.extract_paths:
            paths = extract_paths_from_trace(target_path)
            _console.print(f"[bold]{target_path.name}[/]")
            _console.print(f"  [dim]{len(paths)} path(s) found[/]")
            for path in sorted(paths):
                _console.print(f"  [cyan]{path}[/]")
            return

        # Single file PII scan
        results, mode = run_scan(
            target_dir=target_path.parent,
            model_name=args.model,
            scoring_threshold=args.threshold,
            single_file=target_path,
        )

        if args.json:
            output_json(results, mode)
        else:
            for result in results:
                print_file_results(result, mode, show_matches=args.show_matches)
            print_summary(results, mode)
        return

    # ── Directory mode ──
    if not target_path.is_dir():
        _console.print(f"[red]Error: {target_path} is not a directory or file.[/]")
        sys.exit(1)

    # ── Path extraction mode ──
    if args.extract_paths:
        results, total_unique = run_extract_paths(target_path)
        print_extract_paths_results(results, total_unique)
        return

    # ── PII scanning mode ──
    results, mode = run_scan(
        target_dir=target_path,
        model_name=args.model,
        scoring_threshold=args.threshold,
    )

    if args.json:
        output_json(results, mode)
    else:
        for result in results:
            print_file_results(result, mode, show_matches=args.show_matches)
        print_summary(results, mode)


if __name__ == "__main__":
    main()
