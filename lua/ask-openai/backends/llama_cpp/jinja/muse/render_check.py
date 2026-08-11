#!/usr/bin/env python3
"""Render a request_body through two jinja templates and compare the output.

Takes the `request_body` from an ask-trace JSON (or any payload you'd submit
to a completions endpoint) and renders the full conversation with both
templates, asserting they produce identical output.

The template expects tool-call `arguments` to already be dicts (it raises on
JSON strings), so strings are parsed up front -- applied identically to both
templates so the comparison stays fair.

Usage:
    python3 render_check.py ~/.../1786421590-trace.json
    python3 render_check.py trace.json -o original.jinja -m reformatted.jinja
"""

import argparse
import datetime
import difflib
import json
import sys

import jinja2

# Template context vars that aren't in the request_body; same for both templates.
DEFAULTS = {
    "add_generation_prompt": True,
    "bos_token": "<|begin_of_text|>",
    "knowledge_cutoff": "2026-01-04",
    "reasoning_strength": "high",
    "tool_namespace_descriptions": {},
}


def _parse_tool_call_arguments(messages: list[dict]) -> None:
    """Turn JSON-string tool_call arguments into dicts (template requires dicts)."""
    for message in messages:
        for tc in message.get("tool_calls") or []:
            arguments = tc["function"].get("arguments")
            if isinstance(arguments, str):
                try:
                    tc["function"]["arguments"] = json.loads(arguments)
                except json.JSONDecodeError:
                    pass


def build_context(request_body: dict) -> dict:
    ctx = dict(DEFAULTS)
    messages = request_body.get("messages", [])
    _parse_tool_call_arguments(messages)
    ctx["messages"] = messages
    ctx["tools"] = request_body.get("tools", [])
    if "add_generation_prompt" in request_body:
        ctx["add_generation_prompt"] = request_body["add_generation_prompt"]
    return ctx


def _raise(msg: str) -> None:
    raise RuntimeError(msg)


def render(template_path: str, ctx: dict) -> str:
    # Capture the timestamp once so both templates render with the same value.
    now = datetime.datetime.now()
    env = jinja2.Environment()
    env.globals["strftime_now"] = lambda fmt: now.strftime(fmt)
    env.globals["raise_exception"] = _raise
    template = env.from_string(open(template_path, encoding="utf-8").read())
    return template.render(**ctx)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("trace", help="path to trace JSON (uses .request_body)")
    ap.add_argument("-o", "--orig", default="original.jinja", help="first template")
    ap.add_argument("-m", "--mine", default="reformatted.jinja", help="second template")
    args = ap.parse_args()

    trace = json.load(open(args.trace, encoding="utf-8"))
    request_body = trace.get("request_body", trace)
    ctx = build_context(request_body)
    print(f"rendering {len(ctx['messages'])} messages, {len(ctx['tools'])} tools")

    try:
        orig = render(args.orig, ctx)
        mine = render(args.mine, ctx)
    except Exception as exc:
        print(f"render failed: {exc}")
        return 1

    if orig == mine:
        print(f"MATCH: both templates produced identical output ({len(orig)} chars)")
        return 0

    print(f"MISMATCH: {len(orig)} vs {len(mine)} chars")
    diff = difflib.unified_diff(
        orig.splitlines(), mine.splitlines(),
        fromfile=args.orig, tofile=args.mine, lineterm="",
    )
    for line in diff:
        print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
