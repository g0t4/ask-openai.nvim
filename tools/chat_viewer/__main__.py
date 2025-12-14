import json
import sys
from pathlib import Path
from rich.console import Console
from rich.markdown import Markdown
from rich.padding import Padding
from rich.syntax import Syntax
from typing import Any, Dict, List

from rich.text import Text

_console = Console(color_system="truecolor")

def yank(mapping, key: str, default=None):
    value = mapping.get(key, default)
    if key in mapping:
        del mapping[key]
    return value

def load_thread(file_path: Path) -> List[Dict[str, Any]]:
    with file_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and "messages" in data:
        return data["messages"]
    return data if isinstance(data, list) else []

def insert_newlines(content: str) -> str:
    return content.replace("\\n", "\n")

def _format_json(content: Any) -> str:
    try:
        return json.dumps(content, indent=2)
    except Exception:
        return str(content)

def _extract_content(msg: dict) -> str:
    content = msg.get("content", "")
    if isinstance(content, dict) and "text" in content:
        return content["text"]
    return content  # type: ignore

def _format_content(content: Any) -> str:
    if isinstance(content, str):
        return insert_newlines(content)
    return _format_json(content)

def print_role_markdown(msg: dict, role: str):
    raw_content = _extract_content(msg)
    formatted = raw_content
    _console.print(formatted, markup=False)

def print_tool(msg: Dict[str, Any]):
    content = msg.get("content", "")
    if isinstance(content, dict):
        content = _format_json(content)
    elif isinstance(content, str):
        try:
            parsed = json.loads(content)
            content = _format_json(parsed)
        except Exception:
            content = insert_newlines(content)
    else:
        content = _format_json(content)

    _console.print(content, markup=False)

def _handle_apply_patch(arguments: str):

    try:
        parsed = json.loads(arguments)
    except Exception:
        return arguments

    if isinstance(parsed, dict) and "patch" in parsed:
        patch_content = str(parsed["patch"])
        try:
            syntax = Syntax(patch_content, "diff", theme="ansi_dark", line_numbers=False)
            return syntax
        except Exception:
            return patch_content
    if isinstance(parsed, dict):
        return json.dumps(parsed, ensure_ascii=False)
    return str(parsed)

def _handle_run_command(arguments: str):
    try:
        loaded = json.loads(arguments)
        loaded["cwd"] = "foo"
        command = Syntax(yank(loaded, "command"), "fish", theme="ansi_dark", line_numbers=False)

        if len(loaded.keys()) == 0:
            return command

        remaining_keys = Syntax(
            json.dumps(loaded, ensure_ascii=False, indent=2),
            "json",
            theme="ansi_dark",
            line_numbers=False,
        )
        return [command, "unformatted keys:", remaining_keys]
    except json.JSONDecodeError as e:
        return [Text(arguments)]

def handle_json_args(arguments: str):
    try:
        loaded = json.loads(arguments)
        pretty = json.dumps(loaded, ensure_ascii=False, indent=2)
        return Syntax(pretty, "json", theme="ansi_dark", indent_guides=True, line_numbers=False)
    except json.JSONDecodeError as e:
        return arguments

def _handle_unknown_tool(arguments: str):
    return arguments

def _format_tool_arguments(func_name: str, arguments: str):
    if func_name == "apply_patch":
        return _handle_apply_patch(arguments)
    if func_name == "run_command":
        return _handle_run_command(arguments)
    # semantic_grep has a few json args, that's fine to show
    return handle_json_args(arguments)

def print_assistant(msg: dict):
    content = msg.get("content", "")
    if content:
        _console.print(insert_newlines(content))

    reasoning = msg.get("reasoning_content")
    if reasoning:
        reasoning = insert_newlines(reasoning)
        reasoning_section = f"{reasoning}"
        _console.print(reasoning_section, style="bright_black italic")

    requests = yank(msg, "tool_calls", [])
    if requests:
        for call in requests:
            call_id = yank(call, "id")
            type = yank(call, "type")
            if type != "function":
                # text.append(f"- UNHANDLED TYPE '{type}' on tool call")
                _console.print_json(json.dumps(call))
                continue

            function = yank(call, "function")
            func_name = yank(function, "name")
            arguments = yank(function, "arguments")

            args = _format_tool_arguments(func_name, arguments)

            # TODO if log error if any unexpected fields besides the ones above... that way I am not missing something critical/sensitive when doing a review
            #  TODO for function
            #  TODO for call too (above it)

            _console.print(f"- [bold]{func_name}[/]:")

            if isinstance(args, list):
                for part in args:
                    _console.print(Padding(part, (0, 0, 0, 4)))
            else:
                _console.print(Padding(args, (0, 0, 0, 4)))
            _console.print()

def get_color(role: str) -> str:
    role_lower = role.lower()
    if role_lower == "system":
        return "magenta"
    if role_lower == "developer":
        return "cyan"
    if role_lower == "user":
        return "green"
    if role_lower == "assistant":
        return "yellow"
    if role_lower == "tool":
        return "red"
    return "white"

def print_message(msg: dict):
    role = msg.get("role", "").lower()

    color = get_color(role)
    _console.rule(style=color)
    _console.print(role.upper(), style=color + " bold")
    _console.rule(style=color)

    match role:
        case "system" | "developer" | "user":
            print_role_markdown(msg, role)
        case "tool":
            print_tool(msg)
        case "assistant":
            print_assistant(msg)
        case _:
            print_fallback(msg)

def print_fallback(msg: Dict[str, Any]):
    role = msg.get("role", "")
    content = msg.get("content", "")
    formatted = _format_content(content)

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python -m tools.chat_viewer <thread.json>")
        sys.exit(1)

    thread_file = Path(sys.argv[1])
    if not thread_file.is_file():
        print(f"File not found: {thread_file}")
        sys.exit(1)

    messages = load_thread(thread_file)
    for message in messages:
        print_message(message)

if __name__ == "__main__":
    main()
