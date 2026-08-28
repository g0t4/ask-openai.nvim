"""Formatter helpers for displaying run_xonsh tool calls."""

import json


def parse_run_xonsh_arguments(arguments: str) -> tuple[str, dict]:
    """Return Xonsh code and the remaining tool arguments."""
    parsed = json.loads(arguments)
    if not isinstance(parsed, dict):
        raise ValueError("run_xonsh arguments must be an object")

    code = parsed.pop("code", None)
    if not isinstance(code, str):
        raise ValueError("Missing or invalid code argument")

    return code, parsed
