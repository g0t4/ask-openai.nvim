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


def tokens(path: str) -> list[Token]:
    src = open(path, encoding="utf-8").read()
    out = []
    for lineno, tok_type, value in env.lex(src):
        normalized_value = value
        if tok_type != "data":
            normalized_value = value.strip()
        out.append(Token(lineno, tok_type, value, normalized_value))
    return out


orig = tokens("original.jinja")
mine = tokens("reformatted.jinja")

print("identical:", [t.normalized for t in orig] == [t.normalized for t in mine])
if orig != mine:
    for i, (a, b) in enumerate(zip(orig, mine)):
        if a.normalized != b.normalized:
            print(f"first diff at token {i}: {a!r} vs {b!r}")
            break
        if a.value != b.value:
            console.print(f"literal diff at token {i}: {a.value!r} vs {b.value!r}", style="red")
    if len(orig) != len(mine):
        print(f"length mismatch: {len(orig)} vs {len(mine)} tokens")
