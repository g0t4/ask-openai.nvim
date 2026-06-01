"""Formatter helpers for displaying run_process tool calls.

Handles the argv vs command_line display logic, with smart quoting
for argv elements containing whitespace.
"""

import json

def _quote_argv_element(element: str) -> str:
    """
    Only adds quotes when the element contains whitespace.
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

def format_argv(argv: list[str]) -> str:
    """
    Join argv array into a human-readable string with proper quoting.
    """
    return " ".join(_quote_argv_element(str(arg)) for arg in argv)

def format_run_process_command(arguments: str) -> str:
    """Parse run_process arguments and return a displayable command string.

    Supports three modes:
    - argv: Array of arguments (quoted if they contain whitespace)
    - command_line: Raw shell command string
    - command: Single command string

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
        return format_argv(argv)
    if command:
        return command
    raise ValueError("No command found")
