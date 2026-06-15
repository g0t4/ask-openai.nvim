"""Filetype mapper — canonical file type resolution for RAG indexing.

This module provides a three-layer filetype resolution system:

1. **Extension mapping**: canonical extension → canonical filetype
   (e.g. yml → yaml, sh/fish/zsh/bash → shell)

2. **Filename lookup**: explicit filename → filetype
   (e.g. fish_history → yaml, Makefile → make)

3. **Shebang fallback**: parse #! line for extensionless files
   (e.g. #!/usr/bin/env python3 → py)

The canonical filetype is used as the key for RAG datasets/indexes.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional


EXTENSION_TO_FILETYPE: dict[str, str] = {
    # --- YAML family ---
    "yaml": "yaml",
    "yml": "yaml",

    # --- Shell family ---
    "sh": "bash",
    "bash": "bash",
    "zsh": "zsh",
    "fish": "fish",
    "bashrc": "bash",
    "bash_profile": "bash",
    "bash_aliases": "bash",
    "zshrc": "zsh",
    "zprofile": "zsh",
    "zshenv": "zsh",
    "zlogin": "zsh",
    "zlogout": "zsh",
    "zsh_aliases": "zsh",
    "profile": "bash",
    "inputrc": "bash",

    # --- C family ---
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "cc": "cpp",
    "cxx": "cpp",
    "hpp": "cpp",
    "hh": "cpp",
    "hxx": "cpp",

    # --- Objective-C ---
    "m": "objc",
    "mm": "objc",

    # --- GPU / OpenCL ---
    "cu": "cuda",
    "cuh": "cuda",
    "cl": "opencl",

    # --- Go ---
    "go": "go",

    # --- Rust ---
    "rs": "rust",

    # --- Java ---
    "java": "java",

    # --- JavaScript / TypeScript ---
    "js": "javascript",
    "jsx": "javascript",
    "ts": "typescript",
    "tsx": "typescript",

    # --- Python ---
    "py": "py",
    "pyw": "py",
    "pyi": "py",

    # --- Lua ---
    "lua": "lua",

    # --- HTML ---
    "html": "html",
    "htm": "html",

    # --- JINJA ---
    "j2": "jinja",
    "jinja": "jinja",
    "jinja2": "jinja",

    # --- JSON ---
    "json": "json",

    # --- Markdown ---
    "md": "markdown",
    "mdx": "markdown",
    "mkd": "markdown",

    # --- C# ---
    "cs": "csharp",

    # --- PowerShell ---
    "ps1": "powershell",
    "psm1": "powershell",
    "psd1": "powershell",

    # --- Vim script ---
    "vim": "vim",
    "vmb": "vim",

    # --- Make ---
    "makefile": "make",
    "mk": "make",

    # --- Docker ---
    "dockerfile": "docker",

    # --- TOML ---
    "toml": "toml",

    # --- INI / Config ---
    "ini": "ini",
    "cfg": "ini",

    # --- XML ---
    "xml": "xml",

    # --- CSS ---
    "css": "css",
    "scss": "scss",
    "sass": "scss",
    "less": "less",

    # --- SQL ---
    "sql": "sql",

    # --- Diff / Patch ---
    "diff": "diff",
    "patch": "diff",

    # --- Protobuf ---
    "proto": "protobuf",

    # --- GraphQL ---
    "graphql": "graphql",
    "gql": "graphql",

    # --- Vue ---
    "vue": "vue",

    # --- Svelte ---
    "svelte": "svelte",

    # --- Ruby ---
    "rb": "ruby",
    "erb": "ruby",

    # --- PHP ---
    "php": "php",

    # --- Swift ---
    "swift": "swift",

    # --- Kotlin ---
    "kt": "kotlin",
    "kts": "kotlin",

    # --- Zig ---
    "zig": "zig",

    # --- Haskell ---
    "hs": "haskell",

    # --- OCaml ---
    "ml": "ocaml",
    "mli": "ocaml",

    # --- Erlang ---
    "erl": "erlang",
    "hrl": "erlang",

    # --- Elixir ---
    "ex": "elixir",
    "exs": "elixir",

    # --- Elm ---
    "elm": "elm",

    # --- Clojure ---
    "clj": "clojure",
    "cljs": "clojure",

    # --- R ---
    "r": "r",
    "R": "r",

    # --- Julia ---
    "jl": "julia",

    # --- Perl ---
    "pl": "perl",
    "pm": "perl",
    "pod": "perl",

    # --- Nushell ---
    "nu": "nushell",

    # --- Terraform / HCL ---
    "tf": "hcl",
    "hcl": "hcl",
}


BASENAME_TO_FILETYPE: dict[str, str] = {
    # --- Shell ---
    "Makefile": "make",
    "makefile": "make",
    "GNUmakefile": "make",
    #
    # TODO!FILETYPES finish RETRIEVAL DOMAIN renaming (or SEMANTIC DOMAIN renaming)
    "fish_history": "fish",  # yaml format but fish is the primary purpose so let's map it to fish index!
    #

    # --- Docker ---
    "Dockerfile": "docker",
    "Containerfile": "docker",
    "compose.yaml": "docker",
    "compose.yml": "docker",
    "Dockerfile.j2": "docker",

    # # --- Python --- (none of these are not py?)
    # "setup.py": "py",
    # "conftest.py": "py",
    # "manage.py": "py",
    # "wsgi.py": "py",
    # "app.py": "py",

    # --- Markdown ---
    "LICENSE": "markdown",
    "LICENSE.md": "markdown",
    "README": "markdown",
    "README.md": "markdown",

    # --- Ruby ---
    "Gemfile": "ruby",
    "Rakefile": "ruby",

    # --- Go ---
    "go.mod": "go",
    "go.sum": "go",

    # --- Rust ---
    # "Cargo.toml": "toml",
    # "Cargo.lock": "toml", # I want lock files entirely ignored

    # --- PHP ---
    "composer.json": "json",
    # "composer.lock": "json", # ignore lock files (s/b ignored b/c of using fd command)

    # --- Node.js ---
    "package.json": "json",
    # "yarn.lock": "text",

    # --- Text / misc ---
    "CONTRIBUTING": "markdown",
    "CHANGELOG": "markdown",
    "AUTHORS": "text",
    "COPYING": "text",
}

# TODO add support for ignoring some files all the time...
#  TODO or make these default ignored and provide override if ever needed to not ignore them
# ALWAYS_IGNORED = {
#
#     # --- lock files ---
#     # --- perhaps wildcard matching too or instead of exact: "*.lock" (glob) or /.*\.lock/ (regex)
#     "uv.lock",
#     "package-lock.json",
#     "yarn.lock",
#     "Cargo.lock",
#     "go.sum",
#     "composer.lock",
#     "pnpm-lock.yaml",
#     -- TODO other lock files?
#
#     -- TODO other always ignored file types/names?
# }

SHEBANG_TO_FILETYPE: dict[str, str] = {
    # --- Python ---
    "python": "py",
    "python3": "py",
    "python2": "py",

    # TODO can I skip if it is 1:1 for now... IOTW allow 1:1 if not explicit mapping... so .bash => bash or .perl => perl
    # # --- Ruby ---
    # "ruby": "ruby",

    # # --- Perl ---
    # "perl": "perl",

    # --- Node.js ---
    "node": "javascript",

    # --- YAML / JSON ---
    "editorconfig": "ini",
    "env": "ini",
    "prettierrc": "json",
    "eslintrc": "json",
    "babelrc": "json",
    "jshintrc": "json",
    "npmrc": "ini",
    # "nvmrc": "text", # no idea what this format is actually... and text is not a useful grouping IMO
    # "node-version": "text",

    # --- Shell family ---
    "sh": "bash",
    # "bash": "bash",
    # "zsh": "zsh",
    # "fish": "fish",

    # # --- Lua ---
    # "lua": "lua",

    # # --- PHP ---
    # "php": "php",

    # --- Tcl ---
    "tclsh": "tcl",

    # --- R ---
    "Rscript": "r",

    # # --- Julia ---
    # "julia": "julia",
}

def resolve_vim_filetype(vim_filetype: str):
    # PRN add tests and special mapping if needed, but not before a real problem arises
    return resolve_retrieval_domain(f".{vim_filetype}")

def resolve_retrieval_domain(file_path: str | Path) -> Optional[str]:
    """Resolve the file group for a given file path, this is the group used for querying and indexing related files...
      filetype is not vim's filetype
      best to think of this as a group/family and less about a "type"

    Resolution:
    1. Basename match
    2. Shebang detection + parse + mapping
    3. Extension mapping

    """
    # TODO! check explicit mapping always ahead of everything else (that way even w/ an extension we can remap the filetype)

    file_path = Path(file_path)

    # --- * basename * ---
    basename = file_path.name
    filetype = BASENAME_TO_FILETYPE.get(basename)
    if filetype is not None:
        return filetype

    # --- * shebang * ---
    filetype = _detect_filetype_from_shebang(file_path)
    if filetype is not None:
        return filetype

    # --- * file extension * ---
    ext = file_path.suffix.lstrip(".").lower()
    if not ext:
        return None

    filetype = EXTENSION_TO_FILETYPE.get(ext)
    if filetype is not None:
        return filetype

    return ext


# Matches both:
#   #!/usr/bin/env python3
#   #!/bin/bash
_SHEBANG_RE = re.compile(rb"^#!\s*(?:/usr/bin/env\s+)?(\S+)")


def _detect_filetype_from_shebang(file_path: Path) -> Optional[str]:
    """Parse the shebang line of a file to determine its filetype.

    Handles both /usr/bin/env style and direct paths, including versioned
    interpreters like python3.11 or bash5.2.

    Args:
        file_path: Path to the file (must have no extension).

    Returns:
        Canonical filetype string, or None if no shebang found.
    """
    try:
        with open(file_path, "rb") as f:
            first_line = f.readline(256)  # read up to 256 bytes
    except (OSError, UnicodeDecodeError):
        return None

    match = _SHEBANG_RE.match(first_line)
    if not match:
        return None

    interpreter = match.group(1).decode("utf-8", errors="replace")
    # Extract just the binary name (strip path and version suffix)
    binary_name = Path(interpreter).name

    # Try exact match first
    filetype = SHEBANG_TO_FILETYPE.get(binary_name)
    if filetype is not None:
        return filetype

    # Try matching substring for versioned interpreters
    # e.g. "python3.11" starts with "python3" → py
    for key, value in SHEBANG_TO_FILETYPE.items():
        if binary_name.startswith(key):
            return value

    return binary_name

DEFAULT_INCLUDED_FILETYPES: set[str] = {
    # --- Programming languages ---
    "lua",
    "py",
    "java",
    "javascript",
    "typescript",
    "go",
    "rust",
    "c",
    "cpp",
    "objc",
    "cuda",
    "opencl",
    "csharp",
    "powershell",
    "vim",
    "ruby",
    "php",
    "swift",
    "kotlin",
    "zig",
    "haskell",
    "ocaml",
    "erlang",
    "elixir",
    "elm",
    "clojure",
    "r",
    "julia",
    "perl",
    "nushell",
    "tcl",

    # --- Markup / Data ---
    "html",
    "markdown",
    "json",
    "yaml",
    "xml",
    "toml",
    "ini",
    "sql",
    "graphql",
    "protobuf",
    "vue",
    "svelte",

    # --- Stylesheets ---
    "css",
    "scss",
    "less",

    # --- Shell ---
    "bash",
    "zsh",
    "fish",

    # --- Build / Config ---
    "make",
    "docker",
    "hcl",

    # --- Misc ---
    "diff",
    "text",
}
