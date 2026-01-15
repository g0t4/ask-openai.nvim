import json
import os
import sys
import re
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

PREAPPROVED_FILES: list[re.Pattern | str] = []
SHOW_ALL_FILES = False

def load_preapproved_files() -> None:
    preapproved_path = Path(__file__).with_name("preapproved.txt")
    if not preapproved_path.is_file():
        return
    for raw in preapproved_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()

        is_comment_line = bool(re.match(r'\s*#', line))
        if not line or is_comment_line:
            continue

        if line.startswith("re:"):
            try:
                PREAPPROVED_FILES.append(re.compile(line[3:]))
            except re.error as exc:
                # stop so I can fix it, otherwise I could easily miss this:
                sys.exit(f"Invalid regular expression '{line[3:]}': {exc}\n\nFix this (or comment out the line) to continue...")
        else:
            PREAPPROVED_FILES.append(line)

def is_preapproved(file_path: str) -> bool:
    for pat in PREAPPROVED_FILES:
        if isinstance(pat, re.Pattern):
            if pat.search(file_path):
                return True
        else:
            # strings can be an exact match, or prefix match (startswith)
            if file_path == pat or file_path.startswith(pat):
                return True
    return False

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

def load_thread_messages_from_path(argv1: str) -> list[dict[str, Any]]:
    request_file = Path(argv1)
    if not request_file.is_file():
        print(f"File not found: {request_file}")
        sys.exit(1)
    with request_file.open("r", encoding="utf-8") as f:
        data = json.load(f)
    messages = load_messages(data)

    # * include response message at end of thread
    if "response_message" in data:
        # * thread.json
        response = data["response_message"]
        if isinstance(response, dict):
            response["output.json"] = True
            messages.append(response)
    else:
        # * legacy output.json
        output_path = request_file.parent / "output.json"
        if output_path.is_file():
            with output_path.open("r", encoding="utf-8") as f:
                response = json.load(f)
                if isinstance(response, dict):
                    response["output.json"] = True
                    messages.append(response)

    return messages

def load_messages(data) -> list[dict[str, Any]]:
    if isinstance(data, list):
        # * only has list of messages
        return data
    if isinstance(data, dict):
        if "request_body" in data:
            # * thread.json has request_body.messages
            data = data["request_body"]
        if "messages" in data:
            # typical request body, has messages, tools, temp, etc
            messages = data["messages"]
            del data["messages"]
            # FYI print other properties at the top (i.e. tools)... if some of these nag me I can always write handlers for them to make them pretty too
            #   primary is going to be tools list and that tends to look good as is in JSON b/c it is itself a JSON schema
            print_section_header("UNPROCESSED request.body properties", color="cyan")
            pprint_asis(data)
            return messages
    return []

def load_thread_messages_from_stream(stream) -> list[dict[str, Any]]:
    # assume stream can be:
    #   jq .messages | this
    #   cat *-thread.json | this
    #   cat input-messages.json | this
    data = json.load(stream)
    messages = load_messages(data)

    if "response_message" in data:
        # * thread.json
        response = data["response_message"]
        if isinstance(response, dict):
            response["output.json"] = True
            messages.append(response)
    # FYI cannot assume output.json is related (or any othe file) given this data is from STDIN

    return messages

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

def print_markdown_content(msg: dict, role: str):
    """Render markdown content from a message.

    If the markdown originates from an automatic RAG context (it starts with
    ``# Semantic Grep matches:``), we split the content on file headings of the
    form ``## /path/to/file:line-start-line-end``. For each section we check the
    file against the pre‑approved list; unapproved files are displayed, while
    approved ones are hidden unless the ``--all`` flag is used. Unhidden sections
    are rendered as a fenced code block with a language derived from the file
    extension, preserving the original text.
    """
    raw_content = _extract_content(msg)

    # Detect auto‑generated RAG context blocks.
    if raw_content.startswith("# Semantic Grep matches:"):
        lines = raw_content.splitlines()
        # Skip the first summary line.
        idx = 1
        while idx < len(lines):
            header = lines[idx]
            match = re.match(r"^##\s+(.+?):(\d+)-(\d+)", header)
            if not match:
                # If the line does not match a file heading, just move on.
                idx += 1
                continue

            file_path = match.group(1)
            # Collect the following lines until the next heading or end of input.
            idx += 1
            snippet_lines: list[str] = []
            while idx < len(lines) and not lines[idx].startswith("## "):
                snippet_lines.append(lines[idx])
                idx += 1
            snippet = "\n".join(snippet_lines).strip("\n")

            # Skip pre‑approved files unless the user asked to show all.
            if not SHOW_ALL_FILES and file_path and is_preapproved(str(file_path)):
                continue

            # Render a heading for the match.
            _console.print(f"\n## MATCH {file_path}")
            # Determine a language based on the file extension for syntax highlighting.
            ext = os.path.splitext(file_path)[1].lstrip('.').lower()
            # Use a fenced code block; Syntax provides colourised output.
            syntax = Syntax(snippet, ext or "text", theme="ansi_dark")
            print_asis(syntax)
        return

    # Default handling – render the entire content as markdown.
    highlighted = Syntax(raw_content, "markdown", theme="dracula")
    Console().print(highlighted)

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

        # Skip pre‑approved files unless the user explicitly asked for all.
        if not SHOW_ALL_FILES and file and is_preapproved(str(file)):
            # TODO integrate preapproved file filters elsewhere (i.e. role=user messages have a list of rag matches too in a markdown format                                                        u
            continue

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
    reasoning = msg.get("reasoning_content")
    if reasoning:
        print_asis(
            Padding(
                insert_newlines(reasoning),
                (0, 0, 0, 2),  # top, right, bottom, left
            ),
            # PRN "dim" style would work too, instead of bright_black (only works b/c my theme has that as a white-ish)
            style="bright_black italic",
        )
        # btw nothing wrong with going back to no blank line between reasoning and content... given text style differences:
        print()

    content = msg.get("content", "")
    if content:
        print_asis(insert_newlines(content))

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
    if "output.json" in msg:
        title = f"{title} (output.json)"
    print_section_header(title, get_color(role))

    match role:
        case "system" | "developer" | "user":
            print_markdown_content(msg, role)
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
    global SHOW_ALL_FILES

    if "--all" in sys.argv:
        SHOW_ALL_FILES = True
        sys.argv.remove("--all")

    load_preapproved_files()

    if len(sys.argv) < 2:
        messages = load_thread_messages_from_stream(sys.stdin)
    else:
        messages = load_thread_messages_from_path(sys.argv[1])

    for idx, message in enumerate(messages, start=1):
        print_message(message, idx)

if __name__ == "__main__":
    main()
