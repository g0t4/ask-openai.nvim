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

def _format_markdown(msg: dict, role: str) -> str:
    raw_content = _extract_content(msg)
    md = Markdown(raw_content)
    with _console.capture() as capture:
        _console.print(md)
    formatted = capture.get()
    color = get_color(role)
    return f"[{color}]{role}[/]:\n{formatted}\n"

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
    return f"TOOL:\n{content}\n"

def format_assistant(msg: Dict[str, Any]) -> str:
    content = msg.get("content", "")
    if isinstance(content, dict) and "text" in content:
        content = content["text"]
    if isinstance(content, str):
        content = _format_text(content)
    else:
        content = _format_json(content)
    return f"ASSISTANT:\n{content}\n"

def format_message(msg: Dict[str, Any]) -> str:
    role = msg.get("role", "").lower()
    if role == "system":
        return _format_markdown(msg, "SYSTEM")
    if role == "developer":
        return _format_markdown(msg, "DEVELOPER")
    if role == "user":
        return _format_markdown(msg, "USER")
    if role == "tool":
        return format_tool(msg)
    if role == "assistant":
        return format_assistant(msg)
    return f"{role.upper()}:\n{msg.get('content', '')}\n"

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
