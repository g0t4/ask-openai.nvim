
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

def load_thread(file_path: Path) -> List[Dict[str, Any]]:
    with file_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and "messages" in data:
        return data["messages"]
    return data if isinstance(data, list) else []

def format_message(msg: Dict[str, Any]) -> str:
    role = msg.get("role", "unknown")
    content = msg.get("content", "")
    if isinstance(content, dict) and "text" in content:
        content = content["text"]
    if isinstance(content, str):
        content = content.replace("\\n", "\n")
    else:
        try:
            content = json.dumps(content, indent=2)
        except Exception:
            content = str(content)
    header = f"{role.upper()}:"
    return f"{header}\n{content}\n"

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python -m tools.chat_viewer <thread.json>")
        sys.exit(1)
    thread_file = Path(sys.argv[1])
    if not thread_file.is_file():
        print(f"File not found: {thread_file}")
        sys.exit(1)
    messages = load_thread(thread_file)
    for msg in messages:
        formatted = format_message(msg)
        print(formatted)

if __name__ == "__main__":
    main()



