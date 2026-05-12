import json
import os
import sys
import subprocess
import re
from dataclasses import dataclass, field
from pathlib import Path
from rich.console import Console, Group
from rich.markdown import Markdown
from rich.padding import Padding
from rich.syntax import Syntax
from rich.panel import Panel
from rich.pretty import Pretty, pprint
from rich.text import Text
from rich.tree import Tree
from typing import Any, Iterable, Iterator
import hashlib

from tools.chat_viewer.markdown_utils import split_h2_markdown_sections
from tools.chat_viewer.tree_wrapper import TreeWrapper

_console = Console(color_system="truecolor")

preapproved_file_patterns: list[re.Pattern] = []
SHOW_ALL_FILES = False

EXCLUDED_CONTENT_HASHES: list[str] = [
    # FYI careful w/ trailing \n when computing by hand
    #   cat 1776320801-trace.json | jq --raw-output --join-output .request_body.messages[0].content | sha256
    #      use jq's --join-output which joins lines thus removing \n on end
    #
    # * Rewrites
    "4601994390a24a63f5e38160e15dd11c02361ed2be2af84d1a2ae8e77bc7392b",  # Rewrite msg1 - System Message - #1 "Ground rules" (short list of 9 bullets)
    "f7dae2933320d80989f18d7f3b973ca2fb8b57cfdfa8525736aec8e8c85a1482",  #   ground rules updated
    #
    "832293045d2b0ff4a19379aa4bfd15de6dc268434f85e01306741ca23a0f566c",  # Rewrite msg3 - ## General Code Preferences (very short)
    "3213ad85a96c3647b5ff593803be3f0f412187237932208647df3c4db75bb20d",  # Rewrite -msg? - Lua Code Preferences user message
    #
    # * FIMs
    "7da90487ce9c82207d7f5a884bc68ae2dae75ce0b72b9636b2296760b8633d7d",  # FIM System Message - appears not to have unique values
    "71675b1a7166d68175033a5f256cfa7fe6097d25a9ed1167d3c0d884f03d438e",  # FIM msg 2 - "context that's automatically provided" - matches if NO yanks
    # - won't always match b/c IIRC yanks go at end...
    # OR I could literally do a find on blobs of text to ignore (and use current prompt values for that?)
    # TODO split markdown on headers and look for common sections within the markdown! i.e. here in FIM message 2 it has all context in one message (unlike Rewrite which puts each context item into its own user message)...
    #   so I could also go the route of separate user message for each context item type?
    #
    # * Agents/Tools
    # Agents msg1 System Message
    "771937c4c06bbd93ed1e1a0386a8b8ae0f7ce56f684d1ebf2ed25f084af2f49e",  # intro blurb before ## sections
    #
    "ec8f0516513ef8c3ddfd7a6760b44874f8b8665316323feb104f7aae0df1a00e",  # Ground rules
    "89dfb9bec0ec8587e2c9e9f80480375ddc189b36d515f1d2fae59cd6ad3909dc",  # Ground rules (FIM no \n\n)
    #
    # FYI Tool use will remain b/c it shows directories (well worth seeing each time too)
    "248d4a2751e309453b476914b6ecf1ddb2750a9033e3ecb7eb12f04c14fbd917",  # semantic_grep
    "5b4513e0987158cfbc9225e1535f437eb054f5ca5455759984dcbf7631f56197",  # Fetch tool
    "b870ef7225f0a2b973f266c40ceba102867224ce64709d96ad01c9e532f15ba4",  # Committing
    "f81ca64540efef46c8f15087775bcd0497cfc9705fc25b77fbfda98c526fa696",  # top shelf nerd commands
    "8723daf9f8aefcf1372fa7b721bacee4b75e1024fc4badcfeed8e3d4317b1b8b",  # bad commands
    #
    "27d69e723de7d4ed60e5d8c0b0ef5f9fcae2d4de5d0c152a6c50feb1a021630d",  # apply_patch instructs (huge - worth updating)
    "febf26dcfb6df81560cdb9efe38c9c3691064cb3e2d0b6fc3fe89d0091a508d3",  # 2026-04-16 apply_patch changes (current version)
    "f468af805b3d4832b64ba516ca94b729ec5332524564b4c5e2fc7b4ffaa2c112",  #  agents apply_patch instruction 2026-05-09
    #
    # python code prefs:
    "2a29088b7b85f47b3f55caf9adff674f5e0ab345e4b3a01443f9bef29ff933b3",  # agents user msg3 -  python code preferences (short)
    "7f579161c8af585c55ea5dcc35b79bbee399a3b2f4d0461f4df50e17f34a0866",  # python code prefs updated
    "bd6abb18b2eb841a0fe1e6a89e93227744a24dec391c11034966bd5032716147",  # Python Code Preferences (FIM)
    "c43c46905fcf70315ff3929e76ba70d5190002abc20a24cfb8d2f6d44e11d60f",  ## Python Code Preferences
    #
    "232276fe3bb7baf13ede0343f5c076774b2dbd64be3b010a314b85816f718f31",  # rewrite - fish user prefs
    "4f20f6289174db47cefe46f27829c02078f22ce8717594b10c2551c18a57fca6",  # manually added exclusion
    #
    "0136a4aa31976d7f7e35778c4a94356836e189ceb4f37ccf5fe3aed94dda9780",  # Fish syntax examples
    "b1b230c60a363b6e44b6135d15ff1e8d30e83df41d2adfd079d7209ab6e7234e",  # Fish syntax examples (todo is there a difference in how split sections is working that causes the whole match to be different than partial match for same section content?)... NBD just a possible thing to consider
    #
    "511f32b9bf45f71b8a1a807d3636e9694c2c6ad13cc68166ca6741455eb72df7",  # General project code rules
    "8f9ce1c508b6ed7f217818da62222e65643092d1e679f31cb738153edec72cb0",  # General Code Preferences (FIM one + trailing \n\n) # TODO strip trail new lines before compute hash?
    "f2fea7d3d5637345a1862e068f59c3ac597bb70dbf95d30c32830b082f921cfc",  # General Code Preferences (latest in FIM so no \n\n)
]

def _content_hash(msg: dict[str, Any]) -> str:
    """Return SHA‑256 hash (hex) of the message's raw ``content``."""
    content = msg.get("content", "")
    if not isinstance(content, str):
        # ignore non-string values, when I wanna ignore those I can come in here and add support
        return ""
    return hashlib.sha256(content.encode("utf-8")).hexdigest()

def load_preapproved_files() -> None:
    # Use the user‑level configuration location instead of the repository copy.
    preapproved_path = Path.home() / ".config" / "ask-openai" / "preapproved.txt"
    if not preapproved_path.is_file():
        return
    for raw in preapproved_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()

        is_comment_line = bool(re.match(r'\s*#', line))
        if not line or is_comment_line:
            continue

        try:
            preapproved_file_patterns.append(re.compile(line))
        except re.error as exc:
            sys.exit(f"Invalid regular expression '{line}': {exc}\n\nFix this (or comment out the line) to continue...")

def is_preapproved(file_path: str) -> bool:
    return any(pat.search(file_path) for pat in preapproved_file_patterns)

def _is_entire_content_excluded(msg: dict[str, Any]) -> bool:
    """Return True if the message's content hash is listed in EXCLUDED_CONTENT_HASHES.

    The global SHOW_ALL_FILES flag disables exclusion.
    """
    if SHOW_ALL_FILES:
        return False
    content = msg.get("content", "")
    if not isinstance(content, str):
        return False
    content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
    # print("NON-SYSTEM HASH", content_hash) # useful to log to quickly ignore sections you've changed
    return content_hash in EXCLUDED_CONTENT_HASHES

@dataclass
class SectionDTO:
    # message.content or subset of message.content to show/hide
    content: str
    content_hash: str = field(init=False)
    is_excluded: bool = field(init=False)

    def __post_init__(self) -> None:
        # Compute hash and exclusion flag based on the content.
        self.content_hash = hashlib.sha256(self.content.encode("utf-8")).hexdigest()
        self.is_excluded = not SHOW_ALL_FILES and self.content_hash in EXCLUDED_CONTENT_HASHES

    def get_renderable(self):
        # return RenderGroup(Text(self.content))
        lines = self.content.splitlines()
        header_line = lines[0]  # should be ## line always
        content = "\n".join(lines[1:])
        header_render = Text(header_line, style="bold")

        # * special emphasis on key sections
        emphasize_headings: dict[str, str] = {
            "## Recent yanks (copy to clipboard):": "gray0 bold on deep_pink1",
            # add other mappings here as needed
        }

        for heading, apply_style in emphasize_headings.items():
            if heading in header_line:
                header_render = Text(header_line, style=apply_style)
                break

        body_render = _syntax(content, "markdown")
        return Group(header_render, body_render)

def _split_content_into_sections(content: str) -> list[SectionDTO]:
    whole_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
    if not SHOW_ALL_FILES and whole_hash in EXCLUDED_CONTENT_HASHES:
        # TODO why not just return it with is_excluded = True???
        return []

    return [SectionDTO(content=sec) for sec in split_h2_markdown_sections(content)]

def show_unapproved_rag_matches(content: str) -> bool:
    if not content.strip().startswith('# Semantic Grep matches:'):
        return False

    _console.print("[italic]Detected Semantic Grep matches... excluding based on file path[/]")

    for section in split_h2_markdown_sections(content):
        lines = section.splitlines()
        if not lines:
            continue
        header = lines[0]
        match = re.match(r"^##\s+(.+?):(\d+)-(\d+)", header)
        if not match:
            continue

        file_path = match.group(1)
        # Remaining lines after the header constitute the snippet.
        snippet = "\n".join(lines[1:]).strip("\n")

        if not SHOW_ALL_FILES and is_preapproved(str(file_path)):
            continue

        start_line = match.group(2)
        end_line = match.group(3)
        _console.print(f"\n## MATCH {file_path}:{start_line}-{end_line}")
        ext = os.path.splitext(file_path)[1].lstrip('.').lower()
        syntax = _syntax(snippet, ext or "text")
        _console.print(syntax)

    return True

def print_no_markup(what, **kwargs):
    _console.print(what, markup=False, **kwargs)

def pprint_no_truncate(what):
    # btw expand_all=False is the default and will truncate some sections (shown w/ yellow bg on black text with "...")
    #   for now just always show everything given the review is supposed to be exhaustive and so far I haven't noticed much that is a huge burden
    pprint(what, expand_all=True, indent_guides=False)

def yank(mapping, key: str, default=None):
    value = mapping.get(key, default)
    if key in mapping:
        del mapping[key]
    return value

def load_messages_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for line in lines:
        if line.strip() == "":
            continue
        message = json.loads(line)
        yield message

def load_trace_messages_from_path(argv1: str) -> list[dict[str, Any]]:
    request_file = Path(argv1)
    if not request_file.is_file():
        print(f"File not found: {request_file}")
        sys.exit(1)
    if argv1.endswith("-messages.jsonl"):
        return list(load_messages_jsonl(request_file))

    with request_file.open("r", encoding="utf-8") as f:
        data = json.load(f)
    messages = load_messages(data)

    # * include response message at end of trace
    if "response_message" in data:
        # * trace.json
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

def show_rest_of_request_body_properties(data):
    # typical request body, has messages, tools, temp, etc
    # FYI print other properties at the top (i.e. tools)... if some of these nag me I can always write handlers for them to make them pretty too
    #   primary is going to be tools list and that tends to look good as is in JSON b/c it is itself a JSON schema
    # only show rest of request body in verbose mode (--all)
    print_section_header("UNPROCESSED request.body properties", color="cyan")
    pprint_no_truncate(data)

def load_messages(data) -> list[dict[str, Any]]:
    if isinstance(data, list):
        # * only has list of messages
        return data
    if isinstance(data, dict):
        if "request_body" in data:
            # * -trace.json has request_body.messages
            data = data["request_body"]
        if "messages" in data:
            messages = data["messages"]
            del data["messages"]
            if SHOW_ALL_FILES:
                show_rest_of_request_body_properties(data)
            return messages
    return []

def load_trace_messages_from_stream(stream) -> list[dict[str, Any]]:
    # assume stream can be:
    #   jq .messages | this
    #   cat *-trace.json | this
    #   cat input-messages.json | this
    data = json.load(stream)
    messages = load_messages(data)

    if "response_message" in data:
        # * trace
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
    raw_content = _extract_content(msg)
    if not raw_content:
        return

    if show_unapproved_rag_matches(raw_content):
        return

    sections = _split_content_into_sections(raw_content)
    if not sections:
        return

    for sec in sections:
        if sec.is_excluded:
            continue
        _console.print(f"[dim]HASH: {sec.content_hash}[/]")
        _console.print(sec.get_renderable())

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

        if not SHOW_ALL_FILES and is_preapproved(str(file)):
            continue

        if file:
            _console.print(f"\n## MATCH {counter}: [bold]{file}[/]")
        if isinstance(text, str):
            ext = os.path.splitext(file)[1].lstrip('.').lower() if file else ""
            # YES! this is why this review tool rocks... language specific syntax highlighting!
            syntax = _syntax(text, ext or "text")
            _console.print(syntax)
        else:
            _console.print(f"[red bold]UNEXPECTED 'text' field type (rag matches s/b str only):[/]")
            pprint_no_truncate(text)

        counter += 1

    #  FYI could add a verbose flag to dump full matches (so can see all fields):
    # pprint_asis(content) # for dumping full content
    return True

def print_result_unrecognized(content):
    # FYI this is just a warning to consider adding handlers for it
    _console.print(f"[yellow bold]UNRECOGNIZED RESULT TYPE:[/]")
    pprint_no_truncate(content)

def print_tool_call_result(msg: dict[str, Any]):
    content = msg.get("content", "")
    content = decode_if_json(content)
    if not isinstance(content, dict):
        pprint_no_truncate(content)
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
                print_no_markup(Padding(item_text, (0, 0, 0, 4)))
            else:
                print_no_markup(item_text)

    # verbose dump?
    # print_asis(content)
    return True

def _add_apply_patch(arguments: str, tree: TreeWrapper):
    child = tree.add(format_call_title("apply_patch"))

    try:
        parsed = json.loads(arguments)
    except Exception as err:
        return child.add_error("Failed parsing arguments", err, arguments)

    if isinstance(parsed, dict) and "patch" in parsed:
        patch_content = str(parsed["patch"])
        try:
            syntax = _syntax(patch_content, "diff")
            return child.add(syntax)
        except Exception as err:
            return child.add_error("Failed adding patch", err, patch_content)

    if isinstance(parsed, dict):
        return child.add(json.dumps(parsed, ensure_ascii=False))

    return child.add(str(parsed))

def _syntax(source: str, lexer: str) -> Syntax:
    # is_multi_line = "\n" in source
    return Syntax(
        source,
        lexer,  # i.e. bash/json/etc
        theme="ansi_dark",  # effectively sets default theme which is why I want a _syntax helper
        line_numbers=False)

def _bash(source: str):
    # FYI pygments bash lexer sucks at coloring bash, basically only builtins seem styled... i.e. echo
    # return _syntax(source, "bash")
    return _bash_via_bat_high_contrast(source, language="bash")

def _bash_via_bat_high_contrast(
    content: str,
    language: str | None = None,
    *,
    theme: str = "GitHub",  # bat theme
    plain: bool = True,
):
    # material overhead like 20ms per call to bat... fine for now as the thread viewer loads super fast for now
    #  ~400ms => 800ms for 90 message thread (most tool calls were run_process)

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
    return Panel(  # panel adds border around the code, thicker which helps readability
        Text.from_ansi(proc.stdout),
        style="bold on #EAF4FF",  # High contrast light bg + bold foreground
        border_style="#C8B8A8",
    )
    # return Text.from_ansi(
    #     proc.stdout,
    #     style="bold on #EAF4FF", # High contrast light bg + bold foreground
    # )

def _json(data: dict) -> Syntax:
    # PRN add _pprint_syntax?
    pretty = json.dumps(data, ensure_ascii=False, indent=2)
    return Syntax(
        pretty,
        "json",
        theme="ansi_dark",
        # indent_guides=True,
        # line_numbers=True,
    )

def show_remaining_keys(loaded, tree: TreeWrapper):
    if not any(loaded):
        return
    # FYI basically I want a JSON like dump with leading and trailing { and } which waste space...
    for key in loaded.keys():
        value = loaded.get(key)
        display = Text.from_markup(f"[blue]{key}:[/] ") + Text(value)
        # print as if values are all str/bool/number ... handle list/dict if that arises later
        tree.add(display)

def _add_run_command_and_run_process(arguments: str, call_tree: TreeWrapper):
    try:
        loaded = json.loads(arguments)
        # child.add(_json(loaded)) # debugging
        mode = yank(loaded, "mode")
        if mode:
            call_tree.add(Text.from_markup(f"[bold]legacy {mode=}[/]"))  # Ok to drop this too

        def get_display_command():
            # load all available values so I can look for invalid combinations
            command_line = yank(loaded, "command_line", None)
            argv = yank(loaded, "argv", [])
            command = yank(loaded, "command", None)

            if command_line and argv:
                raise ValueError("Ambiguous run_process - both command_line and argv are set")
            if command_line:
                return command_line
            if argv:
                return " ".join(map(str, argv))
            if command:
                return command
            raise ValueError("No command found")

        call_tree.add(_bash(get_display_command()))
        show_remaining_keys(loaded, call_tree)

    except Exception as err:
        call_tree.add_error("Failed parsing command", err, arguments)

def format_call_title(title):
    return f"- {title}"

def _add_generic_tool(func_name: str, arguments: str, tree: TreeWrapper):
    child = tree.add(format_call_title(func_name))
    try:
        loaded = json.loads(arguments)
        child.add(_json(loaded)) # TODO later switch to TreeWraper.json and other similar/new helpers (I migrated to TreeWrapper without fully embracing its helpers yet)
    except json.JSONDecodeError as e:
        child.add_error("generic tool parse args failed", e, arguments)

def _handle_unknown_tool(arguments: str):
    return arguments

def add_tool_call_request(func_name: str, arguments: str, tree: TreeWrapper) -> tuple[list, list]:
    if func_name == "apply_patch":
        return _add_apply_patch(arguments, tree)

    if func_name in ("run_command", "run_process"):
        child = tree.add(format_call_title(func_name))
        return _add_run_command_and_run_process(arguments, child)

    # FYI semantic_grep works good with generic right now:
    return _add_generic_tool(func_name, arguments, tree)

def print_if_missing_keys(obj, name, tree: TreeWrapper):
    if not any(obj.keys()):
        return

    child = tree.add(f"[red bold]MISSED KEYS on {name}:[/]") \
            .add(_json(obj))

def print_assistant(msg: dict):
    reasoning = msg.get("reasoning_content")
    if reasoning:
        print_no_markup(
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
        print_no_markup(insert_newlines(content))

    requests = yank(msg, "tool_calls", [])
    if requests:
        tree = TreeWrapper("calls", hide_root=True)
        tree.TREE_GUIDES = [("    ", "    ", "    ", "    ")]
        for call in requests:
            id = yank(call, "id")
            call_type = yank(call, "type")
            if call_type != "function":
                tree.add(f"- UNHANDLED TYPE '{call_type}' on tool call id: '{id}'") \
                    .add(_json(call))
                continue

            function = yank(call, "function")
            # function = call.get("function", {}) # FYI use this to test missing keys (doesn't yank)
            func_name = yank(function, "name")
            arguments = yank(function, "arguments")

            print_if_missing_keys(function, "function", tree)
            print_if_missing_keys(call, "call", tree)

            add_tool_call_request(func_name, arguments, tree)

        _console.print(tree)
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

    if role in ("system", "user", "developer"):
        print_markdown_content(msg, role)
        return

    if _is_entire_content_excluded(msg):
        # TODO fold this exclude logic into new exclusion pipeline once refactored
        return
    match role:
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
        messages = load_trace_messages_from_stream(sys.stdin)
    else:
        messages = load_trace_messages_from_path(sys.argv[1])

    for idx, message in enumerate(messages, start=1):
        print_message(message, idx)

if __name__ == "__main__":
    main()
