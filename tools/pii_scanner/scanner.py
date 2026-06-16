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
    single_file: Path | None = None,
) -> tuple[list[FileScanResult], str]:
    """Run PII scan on all JSON files in target_dir, or a single file.

    Args:
        target_dir: Directory to scan for JSON files.
        model_name: If provided, use transformers pipeline with this model.
                    If None, use regex-based detection.
        scoring_threshold: Minimum confidence score to report a finding.
        single_file: Optional single JSON file to scan instead of directory.

    Returns:
        A tuple of (results_list, mode_string).
        mode_string is "regex" or "transformers" indicating which method was used.
    """
    # Single file mode
    if single_file is not None:
        json_files = [single_file]
        _console.print(f"[dim]Scanning single file: {single_file.name}[/]\n")
    else:
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


# ─────────────────────────────────────────────
# Path extraction from trace files
# ─────────────────────────────────────────────

# Pattern that matches POSIX-style file paths
_FILE_PATH_RE = re.compile(
    r'(?<![\w.])'
    r'(?:'
    r'(?:~/[\w.\-~!$&()*+,;=:@%]+(?:/[\w.\-~!$&()*+,;=:@%]+)*)'
    r'|(?:[a-zA-Z]:/[\w.\-~!$&()*+,;=:@%]+(?:/[\w.\-~!$&()*+,;=:@%]+)*)'
    r'|(/' + r'[\w.\-~!$&()*+,;=:@%]+' + r'(?:/[\w.\-~!$&()*+,;=:@%]+)*)'
    r'|(?:\./[\w.\-~!$&()*+,;=:@%]+(?:/[\w.\-~!$&()*+,;=:@%]+)*)'
    r'|(?:\.\./[\w.\-~!$&()*+,;=:@%]+(?:/[\w.\-~!$&()*+,;=:@%]+)*)'
    r'|([\w.\-][\w.\-~!$&()*+,;=:@%]*(?:/[\w.\-~!$&()*+,;=:@%]+)+)'
    r')'
)


# URL pattern to strip before path extraction
_URL_RE = re.compile(r'https?://[^\s<>\"\}\)\],;]+')


def _strip_urls_from_text(text: str) -> str:
    """Remove HTTP/HTTPS URLs from a text string.

    This prevents URLs from being misidentified as file paths.
    """
    return _URL_RE.sub('', text)



def _try_json_decode(value: str) -> Any | None:
    """Attempt to deserialize a string as JSON.

    Returns the parsed object on success, or None if the string is not valid JSON.
    """
    try:
        parsed = json.loads(value)
        return parsed
    except (json.JSONDecodeError, TypeError):
        return None


def _extract_paths_from_value(value: Any) -> list[str]:
    """Recursively extract file paths from a hydrated value.

    For strings: attempt JSON deserialization first. If it succeeds, recurse
    into the result. If it fails, search the string for path patterns.

    For dicts: recurse into all values.
    For lists: recurse into all items.
    """
    found_paths: list[str] = []

    if isinstance(value, str):
        # Strip URLs first to prevent them from being misidentified as paths
        cleaned_value = _strip_urls_from_text(value)
        # First, try to decode as JSON to handle nested serialized objects
        decoded = _try_json_decode(cleaned_value)
        if decoded is not None:
            # Recurse into the decoded structure
            found_paths.extend(_extract_paths_from_value(decoded))
        else:
            # Not JSON — treat as a raw string and search for paths
            matches = [m.group() for m in _FILE_PATH_RE.finditer(cleaned_value)]
            found_paths.extend(matches)

    elif isinstance(value, dict):
        for val in value.values():
            found_paths.extend(_extract_paths_from_value(val))

    elif isinstance(value, list):
        for item in value:
            found_paths.extend(_extract_paths_from_value(item))

    return found_paths


def _extract_paths_from_message(message: dict[str, Any]) -> list[str]:
    """Extract file paths from a single message object.

    Checks:
      - message.content (try JSON decode first)
      - message.reasoning_content (raw string search)
      - message.tool_calls[].function.arguments (try JSON decode, then recurse)
    """
    paths: list[str] = []

    # ── message.content ──
    content = message.get("content")
    if content is not None:
        paths.extend(_extract_paths_from_value(content))

    # ── message.reasoning_content (note: not "reasoning") ──
    reasoning = message.get("reasoning_content")
    if reasoning is not None:
        paths.extend(_extract_paths_from_value(reasoning))

    # ── message.tool_calls[].function.arguments ──
    tool_calls = message.get("tool_calls", [])
    if isinstance(tool_calls, list):
        for tool_call in tool_calls:
            if isinstance(tool_call, dict):
                function = tool_call.get("function")
                if isinstance(function, dict):
                    arguments = function.get("arguments")
                    if arguments is not None:
                        paths.extend(_extract_paths_from_value(arguments))

    return paths



# ─────────────────────────────────────────────
# Path denoising
# ─────────────────────────────────────────────

# JSON-RPC method name prefixes that are not file paths
_JSONRPC_METHOD_PREFIXES = frozenset([
    "notifications/",
    "tasks/",
    "tool/call",
    "tool/instruction",
    "tools/call",
    "request/response",
    "reasoning/content",
    "mcp/fetch",
    "mcp/init",
])

# Known abbreviations/phrases that contain slashes but aren't paths
_ABBREVIATIONS = frozenset([
    "add/remove/replace",
    "and/or",
    "b/w",
    "b/c",
    "s/b",
    "w/o",
    "dict/list",
    "code/message/data",
    "central/cached",
    "format/style",
    "ideas/steps",
    "logging/setLevel",
    "question/statement",
    "title/header",
    "scenarios/tools",
    "task/request",
    "notifications/cancelled",
    "notifications/initialized",
    "notifications/message",
    "notifications/progress",
    "notifications/tasks/status",
    "tool/call",
    "tool/instruction",
    "tools/call",
    "tasks/cancel",
    "tasks/get",
    "tasks/list",
    "tasks/result",
    "request/response",
    "reasoning/content",
    "mcp/fetch",
    "mcp/init.lua",
    "mcp/init",
    "messages/shared.lua",
    "notifications",
])

# Extensions that indicate a real file (not just a directory or method name)
_FILE_EXTENSIONS = frozenset([
    ".lua", ".py", ".js", ".ts", ".rs", ".go", ".c", ".h", ".java",
    ".kt", ".rb", ".swift", ".php", ".cpp", ".cs", ".dart", ".scala",
    ".toml", ".yaml", ".yml", ".json", ".xml", ".md", ".txt", ".sh",
    ".fish", ".zsh", ".bash", ".env", ".jinja", ".css", ".html",
    ".vue", ".svelte", ".graphql", ".proto", ".nix", ".vim",
    ".lua", ".gitignore", ".dockerignore", ".editorconfig",
    ".tf", ".hcl", ".terraform", ".lock",
])

# Common HTML tag names that show up as URL fragments
_HTML_TAGS = frozenset([
    "button", "div", "if", "pre", "span", "script", "web", "selection",
    "readonly", "tool_delegate",
])


def _is_abbreviation(path: str) -> bool:
    """Check if the path is a known English abbreviation/phrase."""
    # Strip leading/trailing punctuation
    stripped = path.strip().rstrip(",.!")
    return stripped in _ABBREVIATIONS


def _is_jsonrpc_method(path: str) -> bool:
    """Check if the path looks like a JSON-RPC method name."""
    for prefix in _JSONRPC_METHOD_PREFIXES:
        if path.startswith(prefix):
            return True
    return False




def _has_line_number_suffix(path: str) -> bool:
    """Check if the path ends with a line number pattern (e.g., file.lua:1:)."""
    # Match patterns like: file.lua:1: or file.lua:616:46:
    if re.search(r'\.[a-zA-Z]+:\d+:', path):
        return True
    return False


def _is_diff_hunk(path: str) -> bool:
    """Check if the path looks like a diff hunk marker (e.g., file.lua-611-)."""
    # Match patterns like: file.lua-611- or file.lua-614-end
    if re.search(r'\.[a-zA-Z]+-\d+-', path):
        return True
    # Match patterns like: file.lua-129----
    if re.search(r'\.[a-zA-Z]+-\d+---', path):
        return True
    return False


def _is_json_value_noise(path: str) -> bool:
    """Check if the path looks like a JSON value converted to string."""
    # Patterns like nil/0/false), true/1/true, etc.
    if re.match(r'(?:nil|true|false|0|1|2|3|4|5|6|7|8|9)/', path):
        return True
    if path.endswith(')'):
        return True
    return False



def _is_diff_marker_prefix(path: str) -> bool:
    """Check if the path has a diff marker prefix (a/ or b/)."""
    # In diffs, a/ and b/ prefixes indicate added/removed files
    if re.match(r'^[ab]/', path):
        return True
    return False


def _is_mime_type(path: str) -> bool:
    """Check if the path looks like a MIME type."""
    # MIME types have format type/subtype with optional parameters
    # Common ones: application/json, text/event-stream, application/json;text/event-stream
    if re.match(r'^application/|^text/', path) and ';' in path:
        return True
    return False


def _has_line_range_suffix(path: str) -> bool:
    """Check if the path ends with a line range pattern (file:0-19, file:15-34)."""
    # Match patterns like: file:0-19 or file:606-625
    if re.search(r':\d+-\d+$', path):
        return True
    return False




def _has_trailing_colon(path: str) -> bool:
    """Check if the path ends with a colon (likely not a real path)."""
    return path.endswith(':')



def _strip_line_number_suffix(path: str) -> str:
    """Strip line number ranges from a path, preserving the file path.

    Examples:
        file.lua:1:       -> file.lua
        file.lua:616:46:  -> file.lua
        file.lua-611-     -> file.lua-611
        file.lua-129----  -> file.lua-129
        file:0-19         -> file
    """
    # Pattern: file.ext-N--- or file.ext-N----- (diff hunk with multiple dashes)
    cleaned = re.sub(r'(\.[a-zA-Z]+-\d+)---.*', r'\1', path)
    
    # Pattern: file.ext-N- (diff hunk with single dash)
    cleaned = re.sub(r'(\.[a-zA-Z]+-\d+)-.*$', r'\1', cleaned)
    
    # Pattern: file.ext:N:M: (line:column with trailing colon or more)
    cleaned = re.sub(r'(\.[a-zA-Z]+:\d+):.*', r'\1', cleaned)
    
    # Pattern: file.ext:N: (line number with trailing colon)
    cleaned = re.sub(r'(\.[a-zA-Z]+):\d+:.*$', r'\1', cleaned)
    
    # Pattern: file.ext:N (single line number at end)
    cleaned = re.sub(r'(\.[a-zA-Z]+):\d+$', r'\1', cleaned)
    
    # Pattern: file:N-M (line range on non-file paths like file:0-19)
    cleaned = re.sub(r':(\d+-\d+)$', '', cleaned)
    
    return cleaned


def _is_html_fragment(path: str) -> bool:
    """Check if the path is likely an HTML tag or URL fragment."""
    # If it has a file extension, it's probably a real file
    has_extension = any(path.endswith(ext) for ext in _FILE_EXTENSIONS)
    if has_extension:
        return False
    # Extract the basename (after last /)
    if "/" in path:
        basename = path.rsplit("/", 1)[-1]
    else:
        basename = path
    # Strip trailing colons (like tools/list:)
    name_no_colon = basename.rstrip(":")
    return name_no_colon in _HTML_TAGS

def _is_short_url_fragment(path: str) -> bool:
    """Check if the path is a short slash-prefixed fragment (likely a URL, not a file)."""
    # Paths starting with / but with only one segment (no extension)
    if not path.startswith("/"):
        return False
    # Must NOT have a file extension
    has_extension = any(path.endswith(ext) for ext in _FILE_EXTENSIONS)
    if has_extension:
        return False
    # Split by / and check segments
    segments = [s for s in path.split("/") if s]
    # Single-segment paths like /button, /div, /mcp are suspicious
    if len(segments) == 1:
        return True
    # Two-segment paths where second is a common English word
    if len(segments) == 2:
        second_word = segments[1].lower().rstrip(":")
        # Filter out obvious non-path patterns
        suspicious_words = frozenset([
            "button", "div", "if", "pre", "span", "script", "web",
            "selection", "readonly",
            "mcp", "tools", "low", "medium",
            "norag", "commands", "commits",
        ])
        if second_word in suspicious_words:
            return True
    return False


def _is_dot_dir_only(path: str) -> bool:
    """Check if path is only a dot-directory (e.g., .config/foo/bar)."""
    # This is actually useful info, so we don't filter it
    return False




def _is_dev_device(path: str) -> bool:
    """Check if the path is a /dev/ special device file."""
    # Match paths like /dev/null, /dev/stdin, /dev/stdout, /dev/stderr
    if re.match(r'^/dev/(null|stdin|stdout|stderr|zero|random|urandom|full|tty|ptmx|console|fd[0-9]+)$', path):
        return True
    return False

def _is_valid_path(path: str) -> bool:
    """Determine if a path is likely a real file path and not noise."""
    # Filter out abbreviations first
    if _is_abbreviation(path):
        return False
    
    # Filter out JSON-RPC methods
    if _is_jsonrpc_method(path):
        return False
    
    # Filter out short URL fragments
    if _is_short_url_fragment(path):
        return False
    
    # Filter out HTML tag fragments
    if _is_html_fragment(path):
        return False
    
    # Filter out /dev/ special device files
    if _is_dev_device(path):
        return False
    
    # Strip line number suffixes (we keep the file, just remove the line info)
    path = _strip_line_number_suffix(path)
    
    # Filter out JSON value noise (nil/0/false), etc.)
    if _is_json_value_noise(path):
        return False
    
    # Filter out diff marker prefixes (a/ or b/)
    if _is_diff_marker_prefix(path):
        return False
    
    # Filter out MIME types
    if _is_mime_type(path):
        return False
    
    # Filter out paths with line range suffixes (file:0-19)
    if _has_line_range_suffix(path):
        return False
    
    # Filter out paths ending with colons
    if _has_trailing_colon(path):
        return False
    
    # Paths with extensions are likely valid
    has_extension = any(path.endswith(ext) for ext in _FILE_EXTENSIONS)
    if has_extension:
        return True
    
    # Tilde paths are almost always valid
    if path.startswith("~"):
        return True
    
    # Absolute paths with multiple segments might be valid
    if path.startswith("/") and path.count("/") >= 2:
        return True
    
    # Relative paths with multiple segments
    if "/" in path:
        segments = path.split("/")
        if len(segments) >= 3:
            return True
    
    return False


def _denoise_paths(paths: list[str]) -> list[str]:
    """Remove noise from extracted paths, keeping only likely real paths."""
    seen: set[str] = set()
    unique_paths: list[str] = []
    
    for path in paths:
        # Normalize: strip leading ./ to deduplicate (./file.lua == file.lua)
        normalized_path = path
        if path.startswith('./'):
            normalized_path = path[2:]
        
        # Strip line number suffixes (e.g., file.lua:1:, file.lua-611-)
        stripped_path = _strip_line_number_suffix(normalized_path)
        
        if stripped_path in seen:
            continue
        seen.add(stripped_path)
        
        if _is_valid_path(stripped_path):
            unique_paths.append(stripped_path)
    
    return unique_paths



def extract_paths_from_trace(trace_path: Path) -> list[str]:
    """Extract all file paths from a single trace JSON file.

    Hydrates the trace object, walks request_body.messages and response_message,
    and collects every file path found.

    Args:
        trace_path: Path to the trace JSON file.

    Returns:
        A list of all file paths found in the trace.
    """
    content, error = load_json_content(trace_path)
    if error:
        _console.print(f"[red]Failed to load {trace_path}: {error}[/]")
        return []

    if not isinstance(content, dict):
        _console.print(f"[yellow]Unexpected top-level structure in {trace_path}[/]")
        return []

    all_paths: list[str] = []

    # ── Walk request_body.messages ──
    request_body = content.get("request_body")
    if isinstance(request_body, dict):
        messages = request_body.get("messages")
        if isinstance(messages, list):
            for message in messages:
                if isinstance(message, dict):
                    all_paths.extend(_extract_paths_from_message(message))

    # ── Walk response_message ──
    response_message = content.get("response_message")
    if isinstance(response_message, dict):
        all_paths.extend(_extract_paths_from_message(response_message))

    # Deduplicate while preserving order
    seen: set[str] = set()
    unique_paths: list[str] = []
    for path in all_paths:
        if path not in seen:
            seen.add(path)
            unique_paths.append(path)

    # Denoise: filter out obvious non-paths (abbreviations, JSON-RPC methods, etc.)
    return _denoise_paths(unique_paths)


def find_trace_files(root_dir: Path) -> list[Path]:
    """Find all *-trace.json files under the given directory (recursive)."""
    return sorted(root_dir.glob("**/*-trace.json"), key=lambda p: p.name)


def run_extract_paths(
    target_dir: Path,
) -> tuple[list[tuple[Path, list[str]]], int]:
    """Extract file paths from all trace files in target_dir.

    Args:
        target_dir: Directory to scan for *-trace.json files.

    Returns:
        A tuple of (file_path_results, total_unique_paths).
        file_path_results is a list of (file_path, sorted_unique_paths) tuples.
        total_unique_paths is the count of globally unique paths across all files.
    """
    trace_files = find_trace_files(target_dir)
    if not trace_files:
        _console.print("[yellow]No *-trace.json files found in target directory.[/]")
        return [], 0

    _console.print(f"[dim]Found {len(trace_files)} trace file(s) to scan.[/]")

    all_global_paths: set[str] = set()
    results: list[tuple[Path, list[str]]] = []

    for trace_file in trace_files:
        paths = extract_paths_from_trace(trace_file)
        sorted_paths = sorted(paths)
        results.append((trace_file, sorted_paths))
        all_global_paths.update(paths)

    return results, len(all_global_paths)


def print_extract_paths_results(
    results: list[tuple[Path, list[str]]],
    total_unique_paths: int,
) -> None:
    """Print the extracted paths results in a readable format.

    Args:
        results: List of (file_path, sorted_paths) tuples.
        total_unique_paths: Total number of globally unique paths.
    """
    for trace_file, sorted_paths in results:
        _console.print(f"[bold]{trace_file.name}[/]")
        _console.print(f"  [dim]{len(sorted_paths)} path(s) found[/]")
        for path in sorted_paths:
            _console.print(f"  [cyan]{path}[/]")
        _console.print()  # blank line separator

    _console.print(f"[bold]Total unique paths across all files:[/] {total_unique_paths}")
