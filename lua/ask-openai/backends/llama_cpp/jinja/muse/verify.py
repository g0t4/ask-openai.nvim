import jinja2
from dataclasses import dataclass
from rich.console import Console
from rich.text import Text

console = Console()

env = jinja2.Environment()


@dataclass(frozen=True)
class Token:
    """DTO for a lexed token, kept post-normalization."""

    lineno: int
    tok_type: str
    value: str
    normalized_value: str

    @property
    def normalized(self) -> tuple[str, str]:
        """Token identity after normalization (type + trimmed value)."""
        return (self.tok_type, self.normalized_value)


def tokenize(src: str) -> list[Token]:
    """Lex a template, dropping semantically-irrelevant whitespace tokens.

    Two whitespace forms are always invisible to rendering and are skipped:
      - `whitespace` tokens: runs of whitespace *inside* jinja tags
      - `data` tokens that are entirely whitespace: whitespace *between* tags
        (trimmed by `-%}` / `{%-` whitespace-control markers)
    """
    out = []
    for lineno, tok_type, value in env.lex(src):
        if tok_type == "whitespace":
            continue
        if tok_type == "data":
            if not value.strip():
                continue
            normalized_value = value
        else:
            normalized_value = value.strip()
        out.append(Token(lineno, tok_type, value, normalized_value))
    return out


def tokens(path: str) -> list[Token]:
    src = open(path, encoding="utf-8").read()
    return tokenize(src)


def verify(orig_src: str, mine_src: str) -> bool:
    """Compare two templates, ignoring whitespace that doesn't affect rendering.

    Prints the first real diff. Literal diffs are reported in red only when
    they involve non-whitespace content; differences that are purely
    whitespace (trimmed by `-%}` / `{%-` control markers) are summarized as a
    count. Returns True when semantically equal.
    """
    orig = tokenize(orig_src)
    mine = tokenize(mine_src)

    print("identical:", [t.normalized for t in orig] == [t.normalized for t in mine])
    whitespace_only = 0
    for a, b in zip(orig, mine):
        if a.normalized != b.normalized:
            print(f"first diff: {a!r} vs {b!r}")
            break
        if a.value != b.value:
            if a.value.strip() == b.value.strip():
                whitespace_only += 1
            else:
                console.print(f"literal diff: {a.value!r} vs {b.value!r}", style="red")
    else:
        if len(orig) != len(mine):
            print(f"length mismatch: {len(orig)} vs {len(mine)} tokens")
        if whitespace_only:
            print(f"skipped {whitespace_only} whitespace-only literal diff(s)")
        return True
    return False


if __name__ == "__main__":
    import sys

    if len(sys.argv) == 3:
        ok = verify(open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read())
    else:
        ok = verify(open("original.jinja", encoding="utf-8").read(), open("reformatted.jinja", encoding="utf-8").read())
    sys.exit(0 if ok else 1)
