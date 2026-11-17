---
description: build first-class Python command-line entrypoints with uv, PATH installation, parser-driven help, and cross-shell completion
---

# Python command-line entrypoints

## Goal

Prefer a real Python entrypoint over shell wrappers for system wide tools and repo-local scripts.

Technically it's more accurate to say `venv-local` because you could easily have multiple `venv`s in one repo. However, most of my repos only have one `venv` in the repo root (hence calling these tools `repo-local`).

The command should become a normal executable on `PATH`.

Do not convert every tiny shell fragment. Just when there's a prominent reusable `tool` that would benefit from convenient access.

## Installation standard

Use the same Python package for local and global installation:


| Type | Command |
|------|---------|
| repo-local tool | uv sync -> auto-activated .venv |
| global tool | uv tool install --editable . |


- My shell has auto-activated venv so any `venv` based tool is always available within the scope of the `.venv`
  - auto-activated upon `cd`ing to a directory with a venv (or one of its nested dirs)
  - auto-deactivated upon `cd`ing out of the directory
- For a repo-local tool, declare it in `pyproject.toml`, run `uv sync`, and rely on the repository's `.venv` auto-activation. The generated console script in `.venv/bin` is the command.
- For a global tool, run `uv tool install --editable <path>`. Do not add a Fish/Xonsh/Bash wrapper that hides a source path or interpreter path/invocation.
- Editable installs make ordinary source changes immediately visible.
- Reinstall or upgrade the tool when entrypoint metadata, dependencies, or build configuration changes.
- Commit `pyproject.toml` and `uv.lock`

## Recommended layout

```
repo
├── .local.xsh
├── pyproject.toml
├── uv.lock
└── tools
    ├── fetch_cats
    │   ├── xompletions
    │   │   └── __init__.py
    │   ├── __main__.py
    │   └── __init__.py
    ├── paint_flowers
    │   ├── browser
    │   │   ├── __main__.py
    │   │   └── __init__.py
    │   ├── xompletions
    │   │   └── __init__.py
    │   ├── tests
    │   │   └── __init__.py
    │   ├── __main__.py
    │   └── __init__.py
    └── __init__.py
```

## Package entrypoint

Declare executables with `[project.scripts]`:

```toml
[build-system]
requires = ["setuptools>=77"]
build-backend = "setuptools.build_meta"

[project]
name = "my-tools"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = ["argcomplete"]

[project.scripts]
fetch_cats = "tools.fetch_cats.__main__:main"
paint_flowers = "tools.paint_flowers.__main__:main"
browser = "tools.paint_flowers.browser.__main__:main"

[tool.setuptools.packages.find]
include = ["tools*"]
```

Use the repository's existing build backend and dependency conventions when present. Do not replace a working project layout merely to match this example.

## One command definition

Keep the command grammar in one importable parser function:

```python
# PYTHON_ARGCOMPLETE_OK

import argparse
from collections.abc import Sequence


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="example-tool",
        description="Operate the example system.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    watch = commands.add_parser(
        "watch",
        help="Follow live activity.",
        description="Follow live activity.",
    )
    watch.add_argument("view", nargs="?", choices=("events", "visual"), default="events")
    watch.set_defaults(handler=run_watch)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    enable_argcomplete(parser)
    args = parser.parse_args(argv)
    return args.handler(args)
```

The same parser should define:

- Subcommands and their descriptions.
- Argument types, defaults, choices, and validation.
- `--help` output.
- Static and dynamic completion candidates.
- Dispatch to small, testable command functions.

Do not maintain separate lists for parser choices, help text, and shell completions.

Use stdlib `argparse` as the portable baseline. If a project already uses another CLI framework, preserve it when it can provide the same single-source command model and completion behavior. Do not add a framework solely to avoid a modest amount of `argparse` code.

## Cross-shell completion

### Bash, Zsh, and Fish

Use `argcomplete` and keep `# PYTHON_ARGCOMPLETE_OK` within the first 1,024 bytes of the console-script module so global completion can recognize generated `[project.scripts]` entrypoints.

```python
def enable_argcomplete(parser: argparse.ArgumentParser) -> None:
    try:
        import argcomplete
    except ImportError:
        # A checkout compatibility entrypoint may still provide ordinary help
        # before `uv sync`; the installed command includes argcomplete.
        return
    argcomplete.autocomplete(parser)
```

Interactive activation examples:

```sh
# Bash or Zsh
eval "$(register-python-argcomplete example-tool)"

# Fish
register-python-argcomplete --shell fish example-tool | source
```

Global argcomplete activation is also acceptable when already part of the user's shell configuration.

### Xonsh

Prefer Xonsh's native `ArgparseCompleter`. It imports the same parser directly, preserving subcommand descriptions and supporting custom argument completers without spawning the command.

Create `xompletions/example_tool.py`:

```python
from xonsh.cli_utils import ArgparseCompleter

from example_tool.cli import build_parser


def xonsh_complete(ctx):
    yield from ArgparseCompleter(build_parser(), command=ctx).complete()
```

Register the repository completion directory in `.local.xsh`:

```xonsh
from pathlib import Path
from xonsh.completers.commands import complete_xompletions

_example_xompletion_dir = str(Path(__file__).with_name("xompletions"))
if _example_xompletion_dir not in $XONSH_COMPLETER_DIRS:
    $XONSH_COMPLETER_DIRS.append(_example_xompletion_dir)
complete_xompletions.wrap(r"\bexample-tool$", "example_tool")
```

Keep execution external. Do not turn an interactive command into a callable Xonsh alias merely to obtain completion; callable aliases can receive captured streams instead of a real TTY. The xompletion module supplies completion while the executable in `.venv/bin` retains normal terminal, redirection, and signal behavior.

For dynamic candidates such as known run IDs, attach a callable to the relevant argparse action:

```python
run_ids = report.add_argument("run_ids", nargs="*", metavar="RUN_ID")
run_ids.completer = known_run_ids
```

## Process and terminal behavior

- Pass subprocess arguments as a list. Avoid `shell=True` and command strings unless shell syntax is the feature being implemented.
- Preserve inherited stdin, stdout, and stderr for interactive commands.
- Use `os.execvp()` or `os.execv()` when a subcommand should become an interactive program such as SSH, a pager, or a TUI.
- Stream long-running output as it arrives. If Python status messages precede child processes, line-buffer or explicitly flush them so captured output retains chronological order.
- Propagate meaningful exit codes. Conventionally return `2` for command-usage errors, the child status for failed delegated commands, `127` for a missing executable, and `130` for interruption.
- Convert expected operational failures into concise messages without tracebacks. Preserve tracebacks for unexpected programming errors unless the project has an established diagnostic mode.
- Forward interruption to managed child processes and clean up pipelines in `finally` blocks.
- Derive repository-relative resources from `Path(__file__).resolve()`, not the current working directory. An installed command must work from any directory.
- When a global editable tool intentionally depends on files in its source checkout, make that coupling explicit. Do not silently assume the caller is inside the repository.

## Migration from shell wrappers

1. Preserve the existing command names, positional arguments, defaults, environment overrides, output streams, and exit behavior unless a change is intentional.
2. Move the implementation into an importable Python package.
3. Add the `[project.scripts]` entrypoint and run `uv sync`.
4. Add parser-driven completion. Prefer a repo-local Xonsh bridge and `argcomplete` for other shells.
5. Keep a tiny old-path compatibility entrypoint only where existing callers require it.
6. Verify the PATH command in a fresh or re-entered shell before removing Fish functions, abbreviations, or path-hiding wrappers.
7. Remove obsolete wrappers only after searching for their callers and confirming the real entrypoint covers their behavior.

Do not perform a mechanical language translation. Use the migration to replace shell-only friction such as manual case parsing, unsafe word splitting, temporary status files, and duplicated validation with appropriate Python structures.

## Verification

Verify the layers that were actually changed:

```sh
uv sync
python -m py_compile example_tool/cli.py
example-tool --help
example-tool watch --help
python -m unittest discover
```

Also check:

- Invalid choices fail with a useful message and nonzero status.
- The installed executable resolves from `.venv/bin` locally or the uv tool directory globally.
- The command runs from outside its source repository.
- Xonsh completion lists subcommands with descriptions and narrows argument choices.
- Dynamic completion returns real current candidates.
- `python -m argcomplete._check_console_script "$(which example-tool)"` accepts the generated entrypoint.
- Interactive subcommands still receive a TTY and respond correctly to interruption.
- At least one representative end-to-end operation succeeds, not only parser unit tests.
- Generated environments and package metadata are ignored while the lockfile remains tracked.

Treat this as a preferred pattern, not a universal rewrite mandate. Use the smallest implementation that produces a real, discoverable, testable command.
