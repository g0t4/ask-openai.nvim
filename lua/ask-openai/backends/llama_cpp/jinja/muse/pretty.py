"""Stupid-simple jinja chat-template formatter.

Breaks each jinja tag onto its own line (indented by block nesting) so
minified templates become legible. Only inserts newlines where whitespace
control (`-`) makes them semantically invisible, so the formatted output
is token-equivalent to the input.

Usage:
    python3 pretty.py original.jinja            # print pretty version
    python3 pretty.py original.jinja -o out.jinja  # write to a file
    python3 pretty.py original.jinja --check    # format + verify equivalence
"""

import argparse
import re
import sys

from verify import verify


BLOCK_BEGIN = {
    "if", "for", "macro", "block", "filter", "with",
    "call", "while", "autoescape", "raw",
}
BLOCK_END = {
    "endif", "endfor", "endmacro", "endblock", "endfilter",
    "endwith", "endcall", "endwhile", "endautoescape", "endraw",
}

# punctuation that attaches without a leading space:  `a.b`, `f(x)`, `x[0]`, `a, b`
NO_SPACE_BEFORE = set(".,()[]")
# punctuation that also attaches without a trailing space:  `a.b`, `f(x)`, `x[0]`
NO_SPACE_AFTER = set(".([")


def first_keyword(tag_text: str) -> str:
    """First word inside a tag, e.g. ``{%- if x -%}`` -> ``if``."""
    m = re.search(r"[%{]-?\s*([A-Za-z_]\w*)", tag_text)
    return m.group(1) if m else ""


def is_left_trim(tag_text: str) -> bool:
    """Tag trims preceding whitespace (``{%-`` / ``{{-``)."""
    return tag_text.startswith("{%-") or tag_text.startswith("{{-")


def is_right_trim(tag_text: str) -> bool:
    """Tag trims following whitespace (``-%}`` / ``-}}``)."""
    return tag_text.endswith("-%}") or tag_text.endswith("-}}")


def join_tag(parts: list[str]) -> str:
    """Join tag tokens into a readable tag, spacing words but not punctuation.

    ``['{%-','if','v','==','1','-%}']`` -> ``{%- if v == 1 -%}``
    ``['{{-','tc','.','name','-}}']``   -> ``{{- tc.name -}}``
    """
    out = parts[0]
    for tok in parts[1:-1]:
        prev_char = out[-1]
        if tok in NO_SPACE_BEFORE or prev_char in NO_SPACE_AFTER:
            out += tok
        else:
            out += " " + tok
    closing = parts[-1]
    if closing and out[-1] not in NO_SPACE_AFTER:
        out += " "
    out += closing
    return out


def group_tokens(src: str) -> list[tuple[str, str]]:
    """Group lexer tokens into (kind, text) items: data chunks or whole tags."""
    import jinja2

    env = jinja2.Environment()
    toks = list(env.lex(src))
    items: list[tuple[str, str]] = []
    i, n = 0, len(toks)
    while i < n:
        _, tok_type, value = toks[i]
        if tok_type == "data":
            items.append(("data", value))
            i += 1
        elif tok_type in ("block_begin", "variable_begin"):
            parts = [value]
            i += 1
            while i < n and toks[i][1] not in ("block_end", "variable_end"):
                if toks[i][1] != "whitespace":
                    parts.append(toks[i][2])
                i += 1
            if i < n:
                parts.append(toks[i][2])
                i += 1
            items.append(("tag", join_tag(parts)))
        else:
            # raw_begin/raw_end and any other standalone token: keep verbatim
            items.append(("tag", value))
            i += 1
    return items


def build_pretty(src: str) -> str:
    """Re-emit tokens with each tag on its own indented line."""
    segments: list[str] = []
    depth = 0
    prev: tuple[str, str] | None = None

    for kind, text in group_tokens(src):
        if kind == "data":
            if text.strip():
                can_break = prev is None or (prev[0] == "tag" and is_right_trim(prev[1]))
                content = ("  " * depth) + text.strip()
                if can_break or not segments:
                    segments.append(content)
                else:
                    segments[-1] += " " + content
                prev = ("data", text)
            # pure-whitespace data: dropped, newlines handled by tags
        else:
            keyword = first_keyword(text)
            if keyword in BLOCK_END:
                depth = max(0, depth - 1)

            can_break = prev is None or (
                (prev[0] == "tag" and is_right_trim(prev[1]) and is_left_trim(text))
                or (prev[0] == "data" and is_left_trim(text))
            )
            # `elif`/`else` continue an `if`/`for` chain: indent them to match
            # their opener. The opener already bumped `depth` (its body sits one
            # level deeper), and its `endif`/`endfor` hasn't fired yet.
            indent = depth - 1 if keyword in ("elif", "else") else depth
            content = ("  " * max(0, indent)) + text
            if can_break or not segments:
                segments.append(content)
            else:
                segments[-1] += " " + text

            prev = ("tag", text)
            if keyword in BLOCK_BEGIN:
                depth += 1

    return "\n".join(segments) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", help="jinja template to format")
    ap.add_argument("-o", "--output", help="write pretty output to this file (default: stdout)")
    ap.add_argument("--check", action="store_true", help="verify formatted output is equivalent to the input")
    args = ap.parse_args()

    src = open(args.input, encoding="utf-8").read()
    pretty = build_pretty(src)

    if args.check:
        print(f"--- verifying {args.input} ---")
        if not verify(src, pretty):
            return 1

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(pretty)
        print(f"wrote {args.output}")
    else:
        sys.stdout.write(pretty)
    return 0


if __name__ == "__main__":
    sys.exit(main())
