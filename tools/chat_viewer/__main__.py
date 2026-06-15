import json
import difflib
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
from typing import Any, Iterable, Iterator, Dict
import hashlib

from tools.chat_viewer.markdown_utils import split_h2_markdown_sections
from tools.chat_viewer.tree_wrapper import TreeWrapper
from tools.chat_viewer.run_process_formatter import commandline_equivalent_for_argv, format_heredoc_stdin
from tools.chat_viewer.timings import ModelTimings, parse_timings, format_stats_line
from tools.chat_viewer.timing_utils import parse_tool_call_timings

# Enable recording so that ``save_html`` can export the rendered output.
_console = Console(color_system="truecolor")

preapproved_file_patterns: list[re.Pattern] = []
SHOW_ALL = False

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
    "0ebaabd61583d43b3f53e5452e2e14be2ecf8cd75d252c4b1eaa91d6e8b9933c",  ## Lua Code Preferences
    "6390f850273cc37a33b54af2656867da990953aa8a77a93b2a5c1331d1acb71e",  ## Lua Code Preferences FIM
    "276286fd2b2f82efa9c50bfe0ca84c66e7eef8d04553570d583ee9c003408690",  ## Lua Code Preferences FIM
    "078f633b1025188833185d8775ad8645be15ff9761cc513a9ca59860ed75ea2d",  ## Lua Code Preferences
    "8311b6b8cce26e1b8f303715cdce15971d11acf00c4489b26649b9ba5674c66a",  ## Lua Code Preferences FIM
    "ca7378d1ca7f4d5422db4b9b07a76757f969560326b87c8cdad01991cceb9e67",  ## Lua Code Preferences Rewrite
    "6371e09bb0e3805cdc9ac8b814d7b5963208272d643559b72fc8febb6e4a37e1",  ## Lua Code Preferences FIM
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
    "f81ca64540efef46c8f15087775bcd0497cfc9705fc25b77fbfda98c526fa696",  # top shelf nerd commands
    "8723daf9f8aefcf1372fa7b721bacee4b75e1024fc4badcfeed8e3d4317b1b8b",  # bad commands
    "96523710d3fe5348152bffddb4c28b3a668bdfd4ef1d5530d826949e83f88afb",  ## BAD COMMANDS
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
    "fc581a8b5aa1c4d88597127dd96b7efbdf42251fa914981850a763fc1331d875",  ## Python Code Preferences
    "a844f2839047f9959d06f26720378f57124635fc89d691d376147926c5ff7c6b",  ## Python Code Preferences
    #
    "232276fe3bb7baf13ede0343f5c076774b2dbd64be3b010a314b85816f718f31",  # rewrite - fish user prefs
    "4f20f6289174db47cefe46f27829c02078f22ce8717594b10c2551c18a57fca6",  # manually added exclusion
    #
    "0136a4aa31976d7f7e35778c4a94356836e189ceb4f37ccf5fe3aed94dda9780",  # Fish syntax examples
    "b1b230c60a363b6e44b6135d15ff1e8d30e83df41d2adfd079d7209ab6e7234e",  # Fish syntax examples (todo is there a difference in how split sections is working that causes the whole match to be different than partial match for same section content?)... NBD just a possible thing to consider
    #
    #
    "b6726077e8204487d5b12facab182f5dc48b85def2dcf72987573cfab3599d22",  ## Fish Shell
    #
    "511f32b9bf45f71b8a1a807d3636e9694c2c6ad13cc68166ca6741455eb72df7",  # General project code rules
    "8f9ce1c508b6ed7f217818da62222e65643092d1e679f31cb738153edec72cb0",  # General Code Preferences (FIM one + trailing \n\n) # TODO strip trail new lines before compute hash?
    "f2fea7d3d5637345a1862e068f59c3ac597bb70dbf95d30c32830b082f921cfc",  # General Code Preferences (latest in FIM so no \n\n)
    "06cac07ff8d9db3035a3d154c21a3088e5ef31342d120e64f0eecc2ee2f71c63",  ## General Code Preferences
    "a67e2c61120110849d3b81f51a76c3ecdcf7b39045da84b92e3055d2016c49ba",  ## General Code Preferences
    #
    "b870ef7225f0a2b973f266c40ceba102867224ce64709d96ad01c9e532f15ba4",  ## Committing (gptoss author)
    "2ddf6ba106f6c037ee986e69a1f0df37b64b8e2501388fff1933a8ffd49333ba",  ## Committing (qwen author)
    #
    "5b4513e0987158cfbc9225e1535f437eb054f5ca5455759984dcbf7631f56197",  ## Fetch tool
    "a9e229dae529161fe195077c1d6c79cc66ab3c37e287a20d9203616f13596d0a",  ## Fetch Tool
]

FIM_PREFIX = "<|fim_prefix|>"
FIM_MIDDLE = "<|fim_middle|>"
FIM_SUFFIX = "<|fim_suffix|>"

def is_raw_completion_fim(data: dict) -> bool:
    """Check if this is a raw completion trace with FIM marker."""
    if not is_raw_completion_trace(data):
        return False

    request_body = data.get("request_body", {})
    prompt = request_body.get("prompt", "")
    return FIM_MIDDLE in prompt

def parse_raw_completion_fim(raw_prompt: str, completion: str) -> dict | None:
    """Parse raw completion with FIM marker into diff components."""
    middle_idx = raw_prompt.find(FIM_MIDDLE)
    prefix_idx = raw_prompt.find(FIM_PREFIX)
    suffix_idx = raw_prompt.find(FIM_SUFFIX)
    if middle_idx < 0 or prefix_idx < 0 or suffix_idx < 0:
        return None

    # we skip everything before FIM_PREFIX (it's only used in repo level FIM where you have other files included before the FIM PSM request
    # prefix is FIM_PREFIX until FIM_SUFFIX
    prefix = raw_prompt[prefix_idx + len(FIM_PREFIX):suffix_idx]
    # suffix is FIM_SUFFIX until FIM_MIDDLE
    suffix = raw_prompt[suffix_idx + len(FIM_SUFFIX):middle_idx]
    return {
        "prefix": prefix,
        "suffix": suffix,
        "completion": completion,
        "diff_type": "fim",
    }

def print_raw_fim_diff(raw_prompt: str, completion: str) -> None:
    """Print a FIM completion diff for raw completions."""
    parsed = parse_raw_completion_fim(raw_prompt, completion)
    if not parsed:
        return

    # Limit context to last 10 lines before and first 10 lines after
    CONTEXT_LINES = 10

    before_lines = parsed["prefix"].split("\n")
    before_omitted = len(before_lines) - CONTEXT_LINES if len(before_lines) > CONTEXT_LINES else 0
    prefix = "\n".join(before_lines[-CONTEXT_LINES:]) if before_omitted > 0 else parsed["prefix"]

    after_lines = parsed["suffix"].split("\n")
    after_omitted = len(after_lines) - CONTEXT_LINES if len(after_lines) > CONTEXT_LINES else 0
    suffix = "\n".join(after_lines[:CONTEXT_LINES]) if after_omitted > 0 else parsed["suffix"]

    old_text = prefix + suffix
    new_text = prefix + completion + suffix

    _console.rule(style="cyan")
    _console.print("[bold cyan]FIM DIFF[/]")
    _console.rule(style="cyan")
    # FYI not a fan of both tree + console.print/rule uses... usually I like trees when I defer print until full output is built... meh for now
    root = TreeWrapper.hidden_root()
    if before_omitted or after_omitted:
        root.add_with_markup("[dim] • Showing 10 lines of context before/after[/]")

    # completions are always INSERTIONS only... so just mark it as green! no need to run a diff
    final_text = Text(prefix) + Text(completion, style="bold italic green") + Text(suffix)
    root.add(final_text)
    root.blank_line()
    _console.print(root)

def is_raw_completion_trace(data: dict) -> bool:
    """Check if this is a raw completion trace (llamacpp /completions endpoint).

    Raw traces have no messages array but have request_body.prompt and top-level content.
    """
    request_body = data.get("request_body", {})
    if not isinstance(request_body, dict):
        return False

    has_prompt = "prompt" in request_body and request_body["prompt"] is not None and request_body["prompt"] != ""
    has_messages = "messages" in request_body
    has_content = "content" in data and data["content"] is not None and data["content"] != ""

    # Raw = has prompt + top-level content, but NO messages
    return has_prompt and has_content and not has_messages

def create_raw_completion_messages(data: dict) -> list[dict]:
    """Create synthetic messages for raw completions (llamacpp /completions endpoint)."""
    messages = []
    request_body = data.get("request_body", {})
    prompt = request_body.get("prompt", "")
    completion = data.get("content", "")

    if prompt:
        messages.append({
            "role": "user_raw",
            "content": prompt,
        })

    if completion:
        messages.append({
            "role": "assistant_raw",
            "content": completion,
        })

    return messages

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

@dataclass
class SectionDTO:
    # message.content or subset of message.content to show/hide
    content: str
    content_hash: str = field(init=False)
    is_excluded: bool = field(init=False)

    def __post_init__(self) -> None:
        # Compute hash and exclusion flag based on the content.
        self.content_hash = hashlib.sha256(self.content.encode("utf-8")).hexdigest()
        self.is_excluded = not SHOW_ALL and self.content_hash in EXCLUDED_CONTENT_HASHES

    def get_renderable(self):
        # return RenderGroup(Text(self.content))
        lines = self.content.splitlines()
        header_line = lines[0]  # should be ## line always
        body = "\n".join(lines[1:])

        # * special emphasis on key sections
        emphasize_headings: dict[str, str] = {
            "## Recent yanks (copy to clipboard):": "gray0 bold on deep_pink1",
            # add other mappings here as needed
        }

        override_header_style = next(
            (style for heading, style in emphasize_headings.items() if heading in header_line),  # note "in" not "==" for matching
            None,
        )
        if override_header_style:
            return Group(Text(header_line, style=override_header_style), _syntax(body, "markdown"))

        # else treat header as markdown too:
        return _syntax(self.content, "markdown")

def _split_content_into_sections(content: str) -> list[SectionDTO]:
    whole_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
    if not SHOW_ALL and whole_hash in EXCLUDED_CONTENT_HASHES:
        # TODO why not just return it with is_excluded = True???
        return []

    return [SectionDTO(content=sec) for sec in split_h2_markdown_sections(content)]

def show_unapproved_auto_rag_matches(content: str) -> bool:
    if not content.strip().startswith('# Semantic Grep matches:'):
        return False

    # FYI no indentation with RAG matches so just use a root tree and everything is top level (headers differentiate sections)
    root = TreeWrapper.hidden_root()
    root.add_with_markup("[italic]Detected Semantic Grep matches... excluding based on file path[/]")

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

        if not SHOW_ALL and is_preapproved(str(file_path)):
            continue

        start_line = match.group(2)
        end_line = match.group(3)

        root.add_with_markup(f"## MATCH [bold]{file_path}[/]:{start_line}-{end_line}")

        ext = os.path.splitext(file_path)[1].lstrip('.').lower()
        root.add(_syntax(snippet, ext or "text"))

        root.blank_line()

    _console.print(root)
    return True

def pprint_no_truncate(what):
    # TODO use new _pretty_no_truncate(what) and then get rid of this old pprint_no_truncate()
    # btw expand_all=False is the default and will truncate some sections (shown w/ yellow bg on black text with "...")
    #   for now just always show everything given the review is supposed to be exhaustive and so far I haven't noticed much that is a huge burden
    pprint(what, expand_all=True, indent_guides=False)

def _pretty_no_truncate(text: Any):
    # ?? was I relying on soft_wrap=True from pprint (this replaced pprint)? if yes, what makes sense in a Tree instead?
    return Pretty(
        text,
        indent_guides=False,
        expand_all=True,
    )

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

def print_model_info(name: str | None, timings: ModelTimings | None = None) -> None:
    """Print model name and optional timing stats.

    Args:
        name: The model name to display.
        timings: Optional ModelTimings object for displaying token counts and timing info.
    """
    if name:
        _console.print(f"[dim]Model:[/] [bold]{name}[/]")
        if timings:
            stats_line = format_stats_line(timings)
            if stats_line:
                _console.print(f"[dim]{stats_line}[/]")
        _console.print()

def load_trace_messages_from_path(trace_file: Path) -> tuple[list[dict[str, Any]], str | None, ModelTimings | None]:
    if not trace_file.is_file():
        print(f"File not found: {trace_file}")
        sys.exit(1)
    if str(trace_file).endswith("-messages.jsonl"):
        return list(load_messages_jsonl(trace_file)), None, None

    with trace_file.open("r", encoding="utf-8") as f:
        data = json.load(f)
    model_name = data.get("last_sse", {}).get("model")
    timings = parse_timings(data.get("last_sse"))
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
        output_path = trace_file.parent / "output.json"
        if output_path.is_file():
            with output_path.open("r", encoding="utf-8") as f:
                response = json.load(f)
                if isinstance(response, dict):
                    response["output.json"] = True
                    messages.append(response)

    return messages, model_name, timings

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
        # Check for raw completions first (llamacpp /completions endpoint)
        if is_raw_completion_trace(data):
            return create_raw_completion_messages(data)

        if "request_body" in data:
            # * -trace.json has request_body.messages
            data = data["request_body"]
        if "messages" in data:
            messages = data["messages"]
            del data["messages"]
            if SHOW_ALL:
                show_rest_of_request_body_properties(data)
            return messages
    return []

def load_trace_messages_from_stream(stream) -> tuple[list[dict[str, Any]], str | None, ModelTimings | None]:
    # assume stream can be:
    #   jq .messages | this
    #   cat *-trace.json | this
    #   cat input-messages.json | this
    data = json.load(stream)
    model_name = data.get("last_sse", {}).get("model")
    timings = parse_timings(data.get("last_sse"))
    messages = load_messages(data)

    if "response_message" in data:
        # * trace
        response = data["response_message"]
        if isinstance(response, dict):
            response["output.json"] = True
            messages.append(response)
    # FYI cannot assume output.json is related (or any othe file) given this data is from STDIN

    return messages, model_name, timings

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

def print_markdown_message(msg: dict):
    raw_content = _extract_content(msg)
    if not raw_content:
        return

    if show_unapproved_auto_rag_matches(raw_content):
        return

    sections = _split_content_into_sections(raw_content)
    if not sections:
        return

    root = TreeWrapper.hidden_root()
    for sec in sections:
        if sec.is_excluded:
            continue
        root.add(f"[dim]HASH: {sec.content_hash}[/]")
        root.add(sec.get_renderable())

    _console.print(root)

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

def _add_rag_matches(root: TreeWrapper, content: Any):
    has_rag_matches = isinstance(content, dict) \
        and "matches" in content \
        and isinstance(content["matches"], list)
    if not has_rag_matches:
        return False

    matches = content["matches"]
    counter = 1  # show counter for easily tracking where I am at in the list
    for match in matches:
        # FYI only file/text are relevant for review (skip rest)
        file = match.get("file")
        end_line_base0 = match.get('end_line_base0')
        start_line_base0 = match.get('start_line_base0')

        skip = not SHOW_ALL and is_preapproved(str(file))
        if skip:
            continue

        header = f"## MATCH {counter}"
        if file:
            header += f": [bold]{file}[/]"
            if isinstance(start_line_base0, int) and isinstance(end_line_base0, int):
                header += f":{start_line_base0+1}-{end_line_base0+1}"
        root.add_with_markup(header)
        # root.add_pretty(match) # useful for troubleshooting... dump it all, beautifully!

        text = match.get("text", "")
        if isinstance(text, str):
            ext = os.path.splitext(file)[1].lstrip('.').lower() if file else ""
            # CAREFUL this uses pygment to syntax highlight (color)... and I am opting into defaults whereas my tree.add_syntax() sets a diff theme
            root.add(_syntax(text, ext or "text"))
        else:
            root.add_with_markup(f"[red bold]UNEXPECTED 'text' field type (rag matches s/b str only):[/]") \
                .add(_pretty_no_truncate(text))
        root.blank_line()

        counter += 1

    #  FYI could add a verbose flag to dump full matches (so can see all fields):
    # pprint_asis(content) # for dumping full content
    return True

def _add_unrecognized(root: TreeWrapper, content: Any) -> None:
    # FYI this is just a warning to consider adding handlers for it
    root.add("[yellow bold]UNRECOGNIZED RESULT TYPE:[/]") \
        .add(_pretty_no_truncate(content))

def print_tool_result_message(msg: Dict[str, Any]) -> None:
    root = TreeWrapper.hidden_root()

    # * show duration if available (for after-the-fact review)
    timings = parse_tool_call_timings(msg)
    if timings:
        root.add(f"[dim]⏱️  {timings.formatted_duration}[/]")

    content = decode_if_json(msg.get("content", ""))
    handled = _add_rag_matches(root, content) or _add_mcp_result(root, content)
    if not handled:
        _add_unrecognized(root, content)

    _console.print(root)

def _add_mcp_result(root: TreeWrapper, content: Any) -> bool:
    has_mcp_content_list = isinstance(content, dict) \
        and ("content" in content) \
        and isinstance(content["content"], list)
    if not has_mcp_content_list:
        return False

    content_list = content["content"]
    for item in content_list:
        item_type = yank(item, "type")
        name = yank(item, "name")
        padding = None
        if name:
            root.add(f"[white]{name}:[/]")
        if item_type == "text":
            item_text = yank(item, "text")
            item_text = insert_newlines(item_text)
            # recognizing markup on tool output is a disaster! that output is never intended for rich printing!
            # you could add tool specific detection or output guessing for syntax highlighting but not worth it for now
            root.add_no_markup(item_text)

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

def _add_run_command_and_run_process(arguments: str, call_tree: TreeWrapper):
    try:
        obj = json.loads(arguments)
        # child.add(_json(loaded)) # debugging
        mode = yank(obj, "mode")
        if mode:
            call_tree.add(Text.from_markup(f"[bold]legacy {mode=}[/]"))  # Ok to drop this too

        def get_display_command():
            # load all available values so I can look for invalid combinations
            command_line = yank(obj, "command_line", None)
            argv = yank(obj, "argv", [])
            command = yank(obj, "command", None)

            if command_line and argv:
                raise ValueError("Ambiguous run_process - both command_line and argv are set")
            if command_line:
                return command_line
            if argv:
                return commandline_equivalent_for_argv(argv)
            if command:
                return command
            raise ValueError("No command found")

        call_tree.add(_bash(get_display_command()))

        # remove fields with special handling
        stdin_text = yank(obj, "stdin_text")

        # rest of fields before stdin_text (TODO or show after?)
        call_tree.list_key_value_pairs(obj)

        # stdin_text as a special nested "file" like block (don't want first line to start after label)
        if stdin_text:
            # btw test case: ~/repos/github/g0t4/datasets/ask_traces/agents/2026-06/2026-06-05_005/1780704102-trace.json
            # FYI I could inline this into the bash command text... but then I cannot differentiate if the model passed the `stdin_text` arg vs literally including the heredoc in the command_line arg
            # the difference might seem subtle but it is the same as knowing wheter the model uses `cwd: 'path/to/foo'` tool arg vs prepending `cd path/to/foo`
            stdin_text = _bash(format_heredoc_stdin(stdin_text))
            # make it look kinda like a HEREDOC but keep it isolated from the command so it is easier to discern
            call_tree.add().add(stdin_text)

    except Exception as err:
        call_tree.add_error("Failed parsing command", err, arguments)

def _add_run_in_neovim(arguments: str, tree: TreeWrapper):
    try:
        obj = json.loads(arguments)
    except Exception as err:
        return tree.add_error("Failed parsing arguments", err, arguments)

    code = obj.get("lua")
    if not isinstance(code, str):
        return tree.add_error("Missing or invalid lua argument", Exception("lua must be a string"), arguments)

    try:
        syntax = _syntax(code, "lua")
        return tree.add(syntax)
    except Exception as err:
        return tree.add_error("Failed adding Lua code", err, code)

def format_call_title(title):
    return f"- {title}"

def _add_generic_tool(func_name: str, args_json_str: str, tree: TreeWrapper):
    child = tree.add(format_call_title(func_name))
    child.list_json_key_value_pairs(args_json_str)

def _handle_unknown_tool(arguments: str):
    return arguments

def add_tool_call_request(func_name: str, arguments: str, tree: TreeWrapper):
    if func_name == "apply_patch":
        return _add_apply_patch(arguments, tree)

    if func_name in ("run_command", "run_process"):
        child = tree.add(format_call_title(func_name))
        return _add_run_command_and_run_process(arguments, child)

    if func_name == "run_in_neovim":
        child = tree.add(format_call_title(func_name))
        return _add_run_in_neovim(arguments, child)

    # FYI semantic_grep works good with generic right now:
    return _add_generic_tool(func_name, arguments, tree)

def print_if_missing_keys(obj, name, tree: TreeWrapper):
    if not any(obj.keys()):
        return

    child = tree.add(f"[red bold]MISSED KEYS on {name}:[/]") \
            .add(_json(obj))

def print_raw_completion_message(msg: dict):
    """Print raw completion message (prompt or completion) verbatim."""
    raw_content = _extract_content(msg)
    if not raw_content:
        return

    root = TreeWrapper.hidden_root()
    root.add_no_markup(raw_content)
    _console.print(root)

def print_assistant_message(msg: dict):
    root = TreeWrapper.hidden_root()

    reasoning = msg.get("reasoning_content")
    if reasoning:
        root.add_no_markup(
            insert_newlines(reasoning),
            style="bright_black italic",
        )
        root.blank_line()

    content = msg.get("content", "")
    if content:
        root.add_no_markup(insert_newlines(content))
        root.blank_line()

    requests = yank(msg, "tool_calls", [])
    if requests:
        for call in requests:
            call_id = yank(call, "id")
            call_type = yank(call, "type")
            if call_type != "function":
                root.add(f"- UNHANDLED TYPE '{call_type}' on tool call id: '{call_id}'") \
                    .add(_json(call))
                continue

            function = yank(call, "function")
            # function = call.get("function", {}) # FYI use this to test missing keys (doesn't yank)
            func_name = yank(function, "name")
            arguments = yank(function, "arguments")

            print_if_missing_keys(function, "function", root)
            print_if_missing_keys(call, "call", root)

            add_tool_call_request(func_name, arguments, root)

    _console.print(root)
    _console.print()  # blank line

def get_display_role(role: str) -> str:
    """Get the display role label for the message title."""
    role_lower = role.lower()
    if role_lower == "user_raw":
        return "PROMPT"
    if role_lower == "assistant_raw":
        return "COMPLETION"
    if role_lower == "tool":
        return "TOOL RESULT"
    return role.upper()

def get_color(role: str) -> str:
    role_lower = role.lower()
    if role_lower == "system":
        return "magenta"
    if role_lower == "developer":
        return "cyan"
    if role_lower == "user" or role_lower == "user_raw":
        return "green"
    if role_lower == "assistant" or role_lower == "assistant_raw":
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
    display_role = get_display_role(role)
    title = f"{idx}: {display_role}"
    if "output.json" in msg:
        title = f"{title} (output.json)"
    print_section_header(title, get_color(role))

    match role:
        case "tool":
            print_tool_result_message(msg)
        case "assistant_raw" | "user_raw":
            print_raw_completion_message(msg)
        case "assistant":
            print_assistant_message(msg)
        case "system" | "developer" | "user" | _:
            print_markdown_message(msg)

def main() -> None:
    global SHOW_ALL

    export_html = False
    html_path: str | None = None

    if "--all" in sys.argv:
        SHOW_ALL = True
        sys.argv.remove("--all")

    if "--html" in sys.argv:
        export_html = True
        sys.argv.remove("--html")
        _console.record = True

    load_preapproved_files()

    if len(sys.argv) < 2:
        messages, model_name, timings = load_trace_messages_from_stream(sys.stdin)
        if export_html:
            html_path = "stdout.html"
    else:
        trace_file = Path(sys.argv[1])
        messages, model_name, timings = load_trace_messages_from_path(trace_file)
        if export_html:
            html_path = str(trace_file) + ".html"

    print_model_info(model_name, timings)

    for idx, message in enumerate(messages, start=1):
        print_message(message, idx)

    # show summaries at end since command line the last part shows first (unlike web viewer where summary is best at top)
    if len(messages) >= 2:
        first_msg = messages[0]
        if first_msg.get("role") == "user_raw" and FIM_MIDDLE in _extract_content(first_msg):
            # Find assistant_raw message
            second_msg = messages[1] if len(messages) > 1 else None
            if second_msg and second_msg.get("role") == "assistant_raw":
                raw_prompt = _extract_content(first_msg)
                raw_completion = _extract_content(second_msg)
                print_raw_fim_diff(raw_prompt, raw_completion)

    if export_html and html_path:
        try:
            _console.save_html(html_path)
        except Exception as e:
            _console.print(f"[red]Failed to write HTML output to {html_path}: {e}[/]")

if __name__ == "__main__":
    main()
