import jinja2

env = jinja2.Environment()

def tokens(path):
    src = open(path, encoding="utf-8").read()
    out = []
    for lineno, tok_type, value in env.lex(src):
        if tok_type != 'data':
            value = value.strip()
        out.append((tok_type, value))
    return out

orig = tokens("original.jinja")
mine = tokens("reformatted.jinja")

print("identical:", orig == mine)
if orig != mine:
    for i, (a, b) in enumerate(zip(orig, mine)):
        if a != b:
            print(f"first diff at token {i}: {a!r} vs {b!r}")
            break
    if len(orig) != len(mine):
        print(f"length mismatch: {len(orig)} vs {len(mine)} tokens")
