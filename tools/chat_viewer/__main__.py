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

def _format_text(content: str) -> str:
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
        return _format_text(content)
    return _format_json(content)

def get_color(role: str) -> str:
    role_lower = role.lower()
    if role_lower == "system":
        return "\x1b[35m"
    if role_lower == "developer":
        return "\x1b[36m"
    if role_lower == "user":
        return "\x1b[32m"
    if role_lower == "assistant":
        return "\x1b[33m"
    if role_lower == "tool":
        return "\x1b[31m"
    return "\x1b[37m"

def print_role_markdown(msg: dict, role: str):
    raw_content = _extract_content(msg)
    formatted = raw_content

    color_code = get_color(role)
    _console.print(f"[green bold]{role.upper()}[/]")
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
            content = _format_text(content)
    else:
        content = _format_json(content)

    _console.print(f"[blue bold]TOOL[/]")
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
    color_code = get_color("assistant")
    reset_code = "\x1b[0m"
    _console.print(f"{color_code}ASSISTANT{reset_code}:")

    content = msg.get("content", "")
    if isinstance(content, dict) and "text" in content:
        content = content["text"]
    if isinstance(content, str):
        content = _format_text(content)
    else:
        content = _format_json(content)
    _console.print(content)

    reasoning = msg.get("reasoning_content")
    if reasoning:
        reasoning_formatted = (_format_text(reasoning) if isinstance(reasoning, str) else _format_json(reasoning))
        reasoning_section = f"\nReasoning:\n{reasoning_formatted}"
    else:
        reasoning_section = ""
    _console.print(reasoning_section)

    # In tools/chat_viewer/__main__.py replace the original block with:
    tool_calls = msg.get("tool_calls", [])
    _console.print("\nTool Calls:\n")
    if tool_calls:
        for call in tool_calls:
            call_id = yank(call, "id")
            type = yank(call, "type")
            if type != "function":
                _console.print(f"- UNHANDLED TYPE '{type}' on tool call")
                _console.print_json(json.dumps(call))
                continue

            function = yank(call, "function")
            func_name = yank(function, "name")
            arguments = yank(function, "arguments")

            args = _format_tool_arguments(func_name, arguments)

            # TODO if log error if any unexpected fields besides the ones above... that way I am not missing something critical/sensitive when doing a review
            #  TODO for function
            #  TODO for call too (above it)

            _console.print(f"- [bold]{func_name}[/]:\n")

            if isinstance(args, list):
                for part in args:
                    _console.print(Padding(part, (0, 0, 0, 4)))
            else:
                _console.print(Padding(args, (0, 0, 0, 4)))
            _console.print()

def print_message(msg: dict):
    role = msg.get("role", "").lower()
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
    color_code = get_color(role.lower())
    reset_code = "\x1b[0m"
    content = msg.get("content", "")
    formatted = _format_content(content)
    _console.print(f"{color_code}{role.upper()}{reset_code}:\n{formatted}\n")

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
