import json
import sys
from pathlib import Path
from rich.console import Console
from rich.markdown import Markdown
from typing import Any, Dict, List

_console = Console()

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

def _format_markdown(msg: dict, role: str) -> str:
    raw_content = _extract_content(msg)
    formatted = raw_content

    color_code = get_color(role)
    reset_code = "\x1b[0m"
    return f"{color_code}{role}{reset_code}:\n{formatted}\n"

def format_tool(msg: Dict[str, Any]) -> str:
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

    color_code = get_color("tool")
    reset_code = "\x1b[0m"
    return f"{color_code}TOOL{reset_code}:\n{content}\n"

def _handle_apply_patch(arguments: str) -> str:
    import json

    try:
        parsed = json.loads(arguments)
    except Exception:
        return arguments

    if isinstance(parsed, dict):
        if "patch" in parsed:
            return str(parsed["patch"])
        return json.dumps(parsed, ensure_ascii=False)
    return str(parsed)

def _handle_run_command(arguments: str) -> str:
    return arguments

def _handle_semantic_grep(arguments: str) -> str:
    return arguments

def _handle_unknown_tool(arguments: str) -> str:
    return arguments

def _format_tool_arguments(func_name: str, arguments: str) -> str:
    if func_name == "apply_patch":
        return _handle_apply_patch(arguments)
    if func_name == "run_command":
        return _handle_run_command(arguments)
    if func_name == "semantic_grep":
        return _handle_semantic_grep(arguments)
    return _handle_unknown_tool(arguments)

def format_assistant(msg: dict) -> str:
    content = msg.get("content", "")
    if isinstance(content, dict) and "text" in content:
        content = content["text"]
    if isinstance(content, str):
        content = _format_text(content)
    else:
        content = _format_json(content)

    reasoning = msg.get("reasoning_content")
    if reasoning:
        reasoning_formatted = (_format_text(reasoning) if isinstance(reasoning, str) else _format_json(reasoning))
        reasoning_section = f"\nReasoning:\n{reasoning_formatted}"
    else:
        reasoning_section = ""

    tool_calls = msg.get("tool_calls", [])
    if tool_calls:
        formatted_calls = []
        for call in tool_calls:
            call_id = call.get("id", "")
            call_type = call.get("type", "")
            function = call.get("function", {})
            func_name = function.get("name", "")
            arguments = function.get("arguments", "")
            displayed_args = _format_tool_arguments(func_name, arguments)
            formatted_calls.append(f"- ID: {call_id}\n  Type: {call_type}\n  Function: {func_name}\n  Arguments: {displayed_args}")
        tool_section = "\nTool Calls:\n" + "\n".join(formatted_calls)
    else:
        tool_section = ""

    color_code = get_color("assistant")
    reset_code = "\x1b[0m"
    return f"{color_code}ASSISTANT{reset_code}:\n{content}{reasoning_section}{tool_section}\n"

def format_message(msg: dict) -> str:
    role = msg.get("role", "").lower()
    match role:
        case "system" | "developer" | "user":
            return _format_markdown(msg, role.upper())
        case "tool":
            return format_tool(msg)
        case "assistant":
            return format_assistant(msg)
        case _:
            return format_fallback(msg)

def format_fallback(msg: Dict[str, Any]) -> str:
    role = msg.get("role", "").upper()
    color_code = get_color(role.lower())
    reset_code = "\x1b[0m"
    content = msg.get("content", "")
    formatted = _format_content(content)
    return f"{color_code}{role}{reset_code}:\n{formatted}\n"

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
        formatted = format_message(message)
        print(formatted)

if __name__ == "__main__":
    main()
