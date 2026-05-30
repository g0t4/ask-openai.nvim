"""Scan JSON files in the current directory for PII.

Supports two modes:
  1. Regex-based detection (default, no dependencies beyond stdlib)
  2. openai/privacy-filter model via transformers (requires latest transformers)
"""

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel

_console = Console(color_system="truecolor")


# ─────────────────────────────────────────────
# PII categories (matching openai/privacy-filter taxonomy)
# ─────────────────────────────────────────────
PII_CATEGORIES: list[str] = [
    "account_number",
    "private_address",
    "private_email",
    "private_person",
    "private_phone",
    "private_url",
    "private_date",
    "secret",
]


@dataclass
class PiIFinding:
    """A single PII detection result."""

    entity_group: str
    text: str
    start_char: int
    end_char: int
    score: float


# ─────────────────────────────────────────────
# Regex-based PII patterns
# ─────────────────────────────────────────────

# Each pattern is (category, compiled_regex, default_score)
PII_PATTERNS: list[tuple[str, re.Pattern, float]] = [
    # Email addresses
    (
        "private_email",
        re.compile(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}'),
        0.95,
    ),
    # Phone numbers (various formats)
    (
        "private_phone",
        re.compile(
            r'(?:\+?1[-.\s]?)?'           # optional country code
            r'(?:\(?\d{3}\)?[-.\s]?)'      # area code
            r'\d{3}[-.\s]?'                # exchange
            r'\d{4}',                       # subscriber
            re.VERBOSE,
        ),
        0.90,
    ),
    # URLs
    (
        "private_url",
        re.compile(r'https?://[^\s<>"\'\}\)]+'),
        0.85,
    ),
    # Secret keys / API tokens (common patterns)
    (
        "secret",
        re.compile(
            r'(?:api[_\-]?key|secret[_\-]?key|token|password|auth)\s*[:=]\s*[\'"]?\S{8,}[\'"]?',
            re.IGNORECASE,
        ),
        0.80,
    ),
    (
        "secret",
        re.compile(r'sk-[a-zA-Z0-9]{20,}'),
        0.95,
    ),
    # Account numbers (generic numeric patterns)
    (
        "account_number",
        re.compile(r'\b(?:account|acct|bank)[_\-]?\s*\d{6,}\b', re.IGNORECASE),
        0.70,
    ),
    # Dates (common formats)
    (
        "private_date",
        re.compile(r'\b\d{4}[-/]\d{2}[-/]\d{2}\b'),
        0.60,
    ),
    # Addresses (very basic heuristic: number + street-type keyword)
    (
        "private_address",
        re.compile(
            r'\b\d{1,5}\s+[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*'
            r'\s+(?:St|Street|Ave|Avenue|Blvd|Boulevard|Dr|Drive|Rd|Road'
            r'|Ln|Lane|Way|Ct|Court|Pl|Place|Pkwy|Parkway)\b',
            re.IGNORECASE,
        ),
        0.70,
    ),
]


# ─────────────────────────────────────────────
# Data classes
# ─────────────────────────────────────────────

@dataclass
class FileScanResult:
    """Scan results for a single file."""

    file_path: Path
    findings: list[PiIFinding] = field(default_factory=list)
    error: str | None = None


# ─────────────────────────────────────────────
# File discovery
# ─────────────────────────────────────────────

def find_json_files(root_dir: Path) -> list[Path]:
    """Find all .json files under the given directory (recursive)."""
    return sorted(root_dir.glob("**/*.json"), key=lambda p: p.name)


def load_json_content(file_path: Path) -> tuple[Any, str | None]:
    """Load and parse a JSON file.

    Returns:
        A tuple of (parsed_content, error_message).
        If error is not None, the content may be None or partial.
    """
    try:
        with file_path.open("r", encoding="utf-8") as f:
            content = json.load(f)
        return content, None
    except json.JSONDecodeError as exc:
        return None, f"Invalid JSON: {exc}"
    except Exception as exc:
        return None, f"Failed to read: {exc}"


# ─────────────────────────────────────────────
# Text extraction from JSON
# ─────────────────────────────────────────────

def extract_text_for_scanning(content: Any) -> list[tuple[str, str]]:
    """Extract text content from a JSON structure for PII scanning.

    Returns a list of (text, source_path) tuples where source_path indicates
    where the text came from (e.g., "root", "$.key.subkey").
    """
    results: list[tuple[str, str]] = []

    def _walk(value: Any, path: str = "root") -> None:
        if isinstance(value, str):
            # Skip short strings and pure-numeric strings (likely IDs, zip codes, etc.)
            if len(value) < 3 or value.strip().isdigit():
                return
            results.append((value, path))
        elif isinstance(value, dict):
            for key, val in value.items():
                _walk(val, f"{path}.{key}")
        elif isinstance(value, list):
            for idx, item in enumerate(value):
                _walk(item, f"{path}[{idx}]")

    _walk(content)
    return results


# ─────────────────────────────────────────────
# Regex-based PII scanning
# ─────────────────────────────────────────────

def scan_for_pii_regex(
    text: str,
    scoring_threshold: float = 0.5,
) -> list[PiIFinding]:
    """Scan a text string for PII using regex patterns.

    Args:
        text: The text to scan.
        scoring_threshold: Minimum score to include a finding.

    Returns:
        List of PiIFinding objects.
    """
    findings: list[PiIFinding] = []
    seen_spans: set[tuple[int, int]] = set()

    for category, pattern, default_score in PII_PATTERNS:
        if default_score < scoring_threshold:
            continue

        for match in pattern.finditer(text):
            start = match.start()
            end = match.end()

            # Skip duplicate overlapping matches
            span_key = (start, end)
            if span_key in seen_spans:
                continue

            # Prefer the longest match if overlapping
            existing = None
            for existing_start, existing_end in list(seen_spans):
                if start <= existing_end and end >= existing_start:
                    existing = (existing_start, existing_end)
                    break

            if existing:
                existing_start, existing_end = existing
                # Keep whichever is longer
                if (end - start) > (existing_end - existing_start):
                    seen_spans.discard(existing)
                    seen_spans.add(span_key)
                else:
                    continue
            else:
                seen_spans.add(span_key)

            findings.append(
                PiIFinding(
                    entity_group=category,
                    text=match.group(),
                    start_char=start,
                    end_char=end,
                    score=default_score,
                )
            )

    # Sort by position in text
    findings.sort(key=lambda f: f.start_char)
    return findings


# ─────────────────────────────────────────────
# Transformers-based PII scanning (optional)
# ─────────────────────────────────────────────

def scan_for_pii_transformers(
    classifier: Any,
    text: str,
    scoring_threshold: float = 0.5,
) -> list[PiIFinding]:
    """Scan a text string for PII using the openai/privacy-filter model.

    Requires transformers >= 4.50+ and the model weights to be downloaded.

    Args:
        classifier: A transformers pipeline instance.
        text: The text to scan.
        scoring_threshold: Minimum confidence score to report a finding.

    Returns:
        List of PiIFinding objects.
    """
    raw_results = classifier(text, aggregation_strategy="simple")

    findings: list[PiIFinding] = []
    for entity in raw_results:
        # Convert numpy float32 to Python float for JSON compatibility
        raw_score = entity.get("score", 0.0)
        score = float(raw_score) if raw_score is not None else 0.0

        is_below_threshold = score < scoring_threshold
        if is_below_threshold:
            continue

        entity_group = entity.get("entity_group", "unknown")
        word = entity.get("word", "")
        start_char = entity.get("start", 0)
        end_char = entity.get("end", len(word))

        findings.append(
            PiIFinding(
                entity_group=entity_group,
                text=word,
                start_char=start_char,
                end_char=end_char,
                score=score,
            )
        )

    return findings


# ─────────────────────────────────────────────
# Result helpers
# ─────────────────────────────────────────────

def group_findings_by_category(findings: list[PiIFinding]) -> dict[str, list[PiIFinding]]:
    """Group findings by their PII category."""
    groups: dict[str, list[PiIFinding]] = {}
    for finding in findings:
        category = finding.entity_group
        if category not in groups:
            groups[category] = []
        groups[category].append(finding)
    return groups


def print_file_results(result: FileScanResult, mode: str, show_matches: bool = False) -> None:
    """Print scan results for a single file using rich formatting.

    Args:
        result: Scan results for a single file.
        mode: Detection mode used ("regex" or "transformers").
        show_matches: If True, display actual PII text instead of masked dots.
    """
    if result.error:
        _console.print(
            Panel(
                f"[red]{result.file_path}[/]\n[dim]{result.error}[/]",
                style="red",
            )
        )
        return

    if not result.findings:
        mode_label = f" ({mode})" if mode else ""
        _console.print(
            f"[green dim]✓ {result.file_path}[/] [dim](no PII detected){mode_label}[/]"
        )
        return

    # Print file header
    _console.print(f"[bold]{result.file_path}[/]")

    # Print count summary
    total = len(result.findings)
    categories = group_findings_by_category(result.findings)
    category_summary = ", ".join(f"{cat}({len(items)})" for cat, items in categories.items())
    _console.print(f"  [dim]{total} finding(s): {category_summary}[/]")

    # Print detailed findings grouped by category
    for category, items in sorted(categories.items()):
        _console.print(f"  [bold yellow]{category}:[/]")
        for item in items:
            if show_matches:
                display_text = f"[red]{item.text}[/]"
            else:
                display_text = f"[{'.' * len(item.text)}]"
            _console.print(
                f"    - {display_text} [dim](score: {item.score:.4f}, pos: {item.start_char}-{item.end_char})[/]"
            )
    _console.print()  # blank line separator


# ─────────────────────────────────────────────
# Main scanning logic
# ─────────────────────────────────────────────

def run_scan(
    target_dir: Path,
    model_name: str | None = None,
    scoring_threshold: float = 0.5,
) -> tuple[list[FileScanResult], str]:
    """Run PII scan on all JSON files in target_dir.

    Args:
        target_dir: Directory to scan for JSON files.
        model_name: If provided, use transformers pipeline with this model.
                    If None, use regex-based detection.
        scoring_threshold: Minimum confidence score to report a finding.

    Returns:
        A tuple of (results_list, mode_string).
        mode_string is "regex" or "transformers" indicating which method was used.
    """
    json_files = find_json_files(target_dir)
    if not json_files:
        _console.print("[yellow]No JSON files found in target directory.[/]")
        return [], "regex"

    # Determine detection mode
    use_transformers = model_name is not None
    if use_transformers:
        _console.print(f"[dim]Loading model: {model_name}[/]")
        try:
            from transformers import pipeline

            classifier = pipeline(
                task="token-classification",
                model=model_name,
                device=0 if _has_cuda() else -1,
            )
            _console.print("[dim]Model loaded.[/]\n")
        except Exception as exc:
            _console.print(
                f"[yellow]Transformers failed ({exc}), falling back to regex.[/]\n"
            )
            use_transformers = False

    mode_label = "transformers" if use_transformers else "regex"
    _console.print(f"[dim]Using {mode_label} detection mode.[/]\n")
    _console.print(f"[dim]Found {len(json_files)} JSON file(s) to scan.[/]\n")

    all_results: list[FileScanResult] = []
    for json_file in json_files:
        content, error = load_json_content(json_file)
        if error:
            all_results.append(FileScanResult(file_path=json_file, error=error))
            continue

        texts_to_scan = extract_text_for_scanning(content)
        if not texts_to_scan:
            all_results.append(FileScanResult(file_path=json_file))
            continue

        file_findings: list[PiIFinding] = []
        for text, source_path in texts_to_scan:
            if use_transformers:
                findings = scan_for_pii_transformers(
                    classifier, text, scoring_threshold
                )
            else:
                findings = scan_for_pii_regex(text, scoring_threshold)

            file_findings.extend(findings)

        all_results.append(
            FileScanResult(file_path=json_file, findings=file_findings)
        )

    return all_results, mode_label


def _has_cuda() -> bool:
    """Check if CUDA is available."""
    try:
        import torch

        return torch.cuda.is_available()
    except ImportError:
        return False


# ─────────────────────────────────────────────
# Summary reporting
# ─────────────────────────────────────────────

def print_summary(
    all_results: list[FileScanResult], mode: str
) -> None:
    """Print a summary table of all scan results."""
    files_with_pii = [r for r in all_results if r.findings]
    files_without_pii = [r for r in all_results if not r.findings and not r.error]
    files_with_errors = [r for r in all_results if r.error]

    total_findings = sum(len(r.findings) for r in all_results)

    from rich.table import Table

    table = Table(title=f"PII Scan Summary ({mode})")
    table.add_column("File", style="cyan")
    table.add_column("Findings", justify="right", style="yellow")
    table.add_column("Status", justify="center")

    for result in all_results:
        finding_count = len(result.findings)
        status = ""
        if result.error:
            status = "[red]Error[/]"
        elif finding_count > 0:
            status = f"[bold red]{finding_count}[/]"
        else:
            status = "[green]Clean[/]"
        table.add_row(str(result.file_path), str(finding_count), status)

    _console.print()
    _console.print(table)
    _console.print()
    _console.print(
        f"[bold]Total files scanned:[/] {len(all_results)}  |  "
        f"[bold]Files with PII:[/] {len(files_with_pii)}  |  "
        f"[bold]Clean files:[/] {len(files_without_pii)}  |  "
        f"[bold]Errors:[/] {len(files_with_errors)}  |  "
        f"[bold]Total findings:[/] {total_findings}"
    )
