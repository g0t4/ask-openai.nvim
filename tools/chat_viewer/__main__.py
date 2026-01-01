import json
import os
import sys
from pathlib import Path
from rich.console import Console
from rich.markdown import Markdown
from rich.padding import Padding
from rich.syntax import Syntax
from rich.panel import Panel
from rich.pretty import Pretty, pprint
from typing import Any

from rich.text import Text

_console = Console(color_system="truecolor")

def print_asis(what, **kwargs):
    _console.print(what, markup=False, **kwargs)

def pprint_asis(what):
    # btw expand_all=False is the default and will truncate some sections (shown w/ yellow bg on black text with "...")
    #   for now just always show everything given the review is supposed to be exhaustive and so far I haven't noticed much that is a huge burden
    pprint(what, expand_all=True, indent_guides=False)

def yank(mapping, key: str, default=None):
    value = mapping.get(key, default)
    if key in mapping:
        del mapping[key]
    return value

def load_thread_messages_from_path(file_path: Path) -> list[dict[str, Any]]:
    with file_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return load_messages(data)

def load_messages(data) -> list[dict[str, Any]]:
    if isinstance(data, dict) and "messages" in data:
        # typical request body, has messages, tools, temp, etc
        messages = data["messages"]
        del data["messages"]
        # FYI print other properties at the top (i.e. tools)... if some of these nag me I can always write handlers for them to make them pretty too
        #   primary is going to be tools list and that tends to look good as is in JSON b/c it is itself a JSON schema
        print_section_header("UNPROCESSED Request Properties", color="cyan")
        pprint_asis(data)
        return messages

    return data if isinstance(data, list) else []

def load_thread_messages_from_stream(stream) -> list[dict[str, Any]]:
    data = json.load(stream)
    return load_messages(data)

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
    print_asis(formatted)

def decode_if_json(content):
    if isinstance(content, str):
        try:
            # return dict/object (or w/e it parses into, if it parses)
            return json.loads(content)
        except Exception:
            # return as str if parse fails
            return insert_newlines(content)

    # keep w/e type (dict, list, etc... don't care)
    return content

def print_rag_matches(content):
    has_rag_matches = "matches" in content and isinstance(content["matches"], list)
    if not has_rag_matches:
        return False
    matches = content["matches"]
    counter = 1  # show counter for easily tracking where I am at in the list
    for match in matches:

        file = match.get("file")
        text = match.get("text", "")
        # FYI no need to show other fields, just file/text are relevant for review, nor warn...
        # unless some other tool at some point has similar matches list and I'd be hiding something

        # TODO! warn if sensitive path

        if file:
            _console.print(f"\n## MATCH {counter}: [bold]{file}[/]")
        if isinstance(text, str):
            ext = os.path.splitext(file)[1].lstrip('.').lower() if file else ""
            # YES! this is why this review tool rocks... language specific syntax highlighting!
            syntax = Syntax(text, ext or "text", theme="ansi_dark", line_numbers=False)
            print_asis(syntax)
        else:
            _console.print(f"[red bold]UNEXPECTED 'text' field type (rag matches s/b str only):[/]")
            pprint_asis(text)

        counter += 1

    #  FYI could add a verbose flag to dump full matches (so can see all fields):
    # pprint_asis(content) # for dumping full content
    return True

def print_result_unrecognized(content):
    # FYI this is just a warning to consider adding handlers for it
    _console.print(f"[yellow bold]UNRECOGNIZED RESULT TYPE:[/]")
    pprint_asis(content)

def print_tool_call_result(msg: dict[str, Any]):
    content = msg.get("content", "")
    content = decode_if_json(content)
    if not isinstance(content, dict):
        pprint_asis(content)
        return

    return print_rag_matches(content) or print_mcp_result(content) or print_result_unrecognized(content)

def print_mcp_result(content):
    has_mcp_content_list = "content" in content and isinstance(content["content"], list)
    if not has_mcp_content_list:
        return False

    content_list = content["content"]
    for item in content_list:
        item_type = yank(item, "type")
        name = yank(item, "name")
        padding = None
        if name:
            _console.print(f"[white]{name}:[/]")
        if item_type == "text":
            item_text = yank(item, "text")
            item_text = insert_newlines(item_text)
            if padding:
                print_asis(Padding(item_text, (0, 0, 0, 4)))
            else:
                print_asis(item_text)

    # verbose dump?
    # print_asis(content)
    return True

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

def print_if_missing_keys(obj, name):
    if not any(obj.keys()):
        return

    _console.print(f"[red bold]MISSED KEYS on {name}:[/]")
    pprint_asis(obj)

def print_assistant(msg: dict):
    content = msg.get("content", "")
    if content:
        print_asis(insert_newlines(content))

    reasoning = msg.get("reasoning_content")
    if reasoning:
        print_asis(
            insert_newlines(reasoning),
            style="bright_black italic",
        )

    requests = yank(msg, "tool_calls", [])
    if requests:
        for call in requests:
            id = yank(call, "id")
            call_type = yank(call, "type")
            if call_type != "function":
                _console.print(f"- UNHANDLED TYPE '{call_type}' on tool call id: '{id}'")
                pprint_asis(call)
                continue

            function = yank(call, "function")
            func_name = yank(function, "name")
            arguments = yank(function, "arguments")
            # arguments = function["arguments"]

            args = _format_tool_arguments(func_name, arguments)

            print_if_missing_keys(function, "function")
            print_if_missing_keys(call, "call")

            _console.print(f"- [bold]{func_name}[/]:")

            if isinstance(args, list):
                for part in args:
                    print_asis(Padding(part, (0, 0, 0, 4)))
            else:
                print_asis(Padding(args, (0, 0, 0, 4)))
            _console.print()  # blank line

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

def print_section_header(title, color):
    _console.rule(style=color)
    _console.print(
        title,
        style=color + " bold",
        highlight=False,
    )  # highlight: False so message numbers stay the same color
    _console.rule(style=color)

def print_message(msg: dict, idx: int):
    role = msg.get("role", "").lower()

    display_role = role.upper()
    if display_role == "TOOL":
        display_role = "TOOL RESULT"
    title = f"{idx}: {display_role}"
    print_section_header(title, get_color(role))

    match role:
        case "system" | "developer" | "user":
            print_role_markdown(msg, role)
        case "tool":
            print_tool_call_result(msg)
        case "assistant":
            print_assistant(msg)
        case _:
            print_fallback(msg)

def print_fallback(msg: dict[str, Any]):
    role = msg.get("role", "")
    content = msg.get("content", "")
    formatted = _format_content(content)

def main() -> None:
    if len(sys.argv) < 2:
        messages = load_thread_messages_from_stream(sys.stdin)
    else:
        thread_file = Path(sys.argv[1])
        if not thread_file.is_file():
            print(f"File not found: {thread_file}")
            sys.exit(1)
        messages = load_thread_messages_from_path(thread_file)

    for idx, message in enumerate(messages, start=1):
        print_message(message, idx)

if __name__ == "__main__":
    main()
