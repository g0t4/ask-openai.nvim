"""Dump run_process commands from a trace file.

Extracts and displays all run_process / run_command tool calls from a trace,
showing both command_line and argv styles with bash syntax highlighting.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax
from rich.text import Text

_console = Console(color_system="truecolor")


def _bash_via_bat_high_contrast(
    content: str,
    language: str | None = None,
    *,
    theme: str = "GitHub",
    plain: bool = True,
) -> Panel:
    """Render bash/text content via bat with high-contrast styling.

    Args:
        content: The text to render.
        language: Pygments/bat language identifier (e.g. 'bash', 'json').
        theme: bat color theme.
        plain: Use --style=plain (no line numbers/box).

    Returns:
        A rich Panel with the highlighted output.
    """
    cmd = [
        "bat",
        "--color=always",
        f"--theme={theme}",
    ]

    if plain:
        cmd.append("--style=plain")

    if language:
        cmd.append(f"--language={language}")

    proc = subprocess.run(
        cmd,
        input=content,
        capture_output=True,
        text=True,
        check=True,
    )
    return Panel(
        Text.from_ansi(proc.stdout),
        style="bold on #EAF4FF",
        border_style="#C8B8A8",
    )


def _format_command_line(arguments: str) -> str:
    """Parse run_process arguments and return a displayable command string.

    Supports three modes:
    - argv: Array of arguments (quoted if they contain whitespace)
    - command_line: Raw shell command string
    - command: Single command string (legacy)

    Args:
        arguments: JSON string of arguments from the tool call.

    Returns:
        A formatted command string ready for display.

    Raises:
        json.JSONDecodeError: If arguments is not valid JSON.
        ValueError: If arguments are ambiguous or missing.
    """
    obj = json.loads(arguments)

    command_line = obj.get("command_line")
    argv = obj.get("argv", [])
    command = obj.get("command")  # legacy name

    if command_line and argv:
        raise ValueError("Ambiguous run_process - both command_line and argv are set")

    if command_line:
        return command_line
    if argv:
        return " ".join(_quote_argv_element(str(arg)) for arg in argv)
    if command:
        return command
    raise ValueError("No command found")


def _quote_argv_element(element: str) -> str:
    """Quote an argv element only when it contains whitespace.

    Uses double quotes by default, falling back to single quotes
    or escaped double quotes if both quote types are present.

    Args:
        element: A single argument from the argv array.

    Returns:
        The element, quoted if it contains whitespace.
    """
    has_whitespace = any(char.isspace() for char in element)
    if not has_whitespace:
        return element

    if '"' not in element:
        return f'"{element}"'
    if "'" not in element:
        return f"'{element}'"

    escaped = element.replace('"', '\\"')
    return f'"{escaped}"'


def _extract_run_process_calls(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Extract all run_process / run_command tool calls from messages.

    Args:
        messages: The messages array from a trace file's request_body.

    Returns:
        List of dicts with 'func_name' and 'display_command' keys.
    """
    commands: list[dict[str, Any]] = []

    for msg in messages:
        if msg.get("role") != "assistant":
            continue

        tool_calls = msg.get("tool_calls", [])
        if not tool_calls:
            continue

        for call in tool_calls:
            function = call.get("function", {})
            func_name = function.get("name", "")
            arguments = function.get("arguments", "")

            if func_name not in ("run_process", "run_command"):
                continue

            try:
                display_command = _format_command_line(arguments)
            except (json.JSONDecodeError, ValueError) as exc:
                display_command = f"[red]Failed to parse: {exc}[/]"

            commands.append({
                "func_name": func_name,
                "display_command": display_command,
            })

    return commands


def load_trace_messages(trace_file: Path) -> list[dict[str, Any]]:
    """Load messages from a trace file.

    Args:
        trace_file: Path to the -trace.json file.

    Returns:
        The messages array from the trace.

    Raises:
        SystemExit: If the file is not found or not a valid trace.
    """
    if not trace_file.is_file():
        print(f"File not found: {trace_file}", file=sys.stderr)
        sys.exit(1)

    with trace_file.open("r", encoding="utf-8") as f:
        data = json.load(f)

    request_body = data.get("request_body", {})
    if isinstance(request_body, dict):
        messages = request_body.get("messages", [])
    elif isinstance(data, list):
        messages = data
    else:
        messages = []

    return messages


def dump_commands(commands: list[dict[str, Any]], plain_text: bool) -> None:
    """Render a numbered list of run_process commands with syntax highlighting.

    Args:
        commands: List of command dicts from _extract_run_process_calls().
        plain_text: If True, output without colors or panel borders.
    """
    if plain_text:
        console = Console(force_terminal=True, color_system=None)
    else:
        console = _console

    if not commands:
        console.print("[dim]No run_process commands found.[/]")
        return

    for idx, cmd_info in enumerate(commands, start=1):
        func_name = cmd_info["func_name"]
        display_command = cmd_info["display_command"]

        console.rule(f"[cyan]{idx}. {func_name}[/]")

        if plain_text:
            # Plain text mode: no colors, no panels, just raw command text
            console.print(display_command)
        else:
            # Styled mode: bat + panel with borders
            console.print(_bash_via_bat_high_contrast(display_command, language="bash"))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments.

    Args:
        argv: Argument list (defaults to sys.argv[1:]).

    Returns:
        Parsed namespace with trace_file and plain_text attributes.
    """
    parser = argparse.ArgumentParser(
        description="Dump run_process commands from a trace file.",
    )
    parser.add_argument(
        "trace_file",
        help="Path to the -trace.json file to analyze.",
    )
    parser.add_argument(
        "--plain-text",
        action="store_true",
        default=False,
        help="Output plain text without colors or panel borders.",
    )
    return parser.parse_args(argv)


def main() -> None:
    """Entry point for trace_dump."""
    args = parse_args()

    trace_file = Path(args.trace_file)
    messages = load_trace_messages(trace_file)
    commands = _extract_run_process_calls(messages)
    dump_commands(commands, plain_text=args.plain_text)


if __name__ == "__main__":
    main()
