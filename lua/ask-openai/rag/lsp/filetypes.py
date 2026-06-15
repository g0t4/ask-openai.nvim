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


# ---------------------------------------------------------------------------
# Layer 1: Extension → Canonical Filetype Mapping
# ---------------------------------------------------------------------------

# Maps raw file extensions to their canonical filetype name.
# Grouping related extensions together (e.g. shell family → "shell").
EXTENSION_TO_FILETYPE: dict[str, str] = {
    # --- YAML family ---
    "yaml": "yaml",
    "yml": "yaml",

    # --- Shell family ---
    "sh": "shell",
    "bash": "shell",
    "zsh": "shell",
    "fish": "shell",

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


# ---------------------------------------------------------------------------
# Layer 2: Explicit Filename → Filetype Mapping
# ---------------------------------------------------------------------------

# Maps specific filenames (case-sensitive) to their canonical filetype.
# These files have no extension but are well-known types.
FILENAME_TO_FILETYPE: dict[str, str] = {
    # --- Shell ---
    "Makefile": "make",
    "makefile": "make",
    "GNUmakefile": "make",
    ".bashrc": "shell",
    ".bash_profile": "shell",
    ".zshrc": "shell",
    ".zprofile": "shell",
    ".zshenv": "shell",
    ".zlogin": "shell",
    ".zlogout": "shell",
    ".profile": "shell",
    ".inputrc": "shell",
    "fish_history": "yaml",
    ".gitignore": "diff",
    ".gitattributes": "ini",
    ".gitconfig": "ini",
    ".gitmodules": "ini",

    # --- Docker ---
    "Dockerfile": "docker",
    "Containerfile": "docker",

    # --- YAML / JSON ---
    ".editorconfig": "ini",
    ".env": "ini",
    ".prettierrc": "json",
    ".eslintrc": "json",
    ".babelrc": "json",
    ".jshintrc": "json",

    # --- Python ---
    "setup.py": "py",
    "conftest.py": "py",
    "manage.py": "py",
    "wsgi.py": "py",
    "app.py": "py",

    # --- Shell ---
    ".bash_aliases": "shell",
    ".zsh_aliases": "shell",

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
    "Cargo.toml": "toml",
    "Cargo.lock": "toml",

    # --- PHP ---
    "composer.json": "json",
    "composer.lock": "json",

    # --- Node.js ---
    "package.json": "json",
    "package-lock.json": "json",
    "yarn.lock": "text",
    ".npmrc": "ini",
    ".nvmrc": "text",
    ".node-version": "text",

    # --- Terraform ---
    ".terraform.lock.hcl": "hcl",

    # --- Text / misc ---
    "CONTRIBUTING": "markdown",
    "CHANGELOG": "markdown",
    "AUTHORS": "text",
    "COPYING": "text",
}


# ---------------------------------------------------------------------------
# Layer 3: Shebang → Filetype Mapping
# ---------------------------------------------------------------------------

# Maps common shebang interpreters to canonical filetypes.
SHEBANG_TO_FILETYPE: dict[str, str] = {
    # --- Python ---
    "python": "py",
    "python3": "py",
    "python2": "py",

    # --- Ruby ---
    "ruby": "ruby",

    # --- Perl ---
    "perl": "perl",

    # --- Node.js ---
    "node": "javascript",

    # --- Shell family ---
    "bash": "shell",
    "sh": "shell",
    "zsh": "shell",
    "fish": "shell",

    # --- Lua ---
    "lua": "lua",

    # --- PHP ---
    "php": "php",

    # --- Tcl ---
    "tclsh": "tcl",

    # --- R ---
    "Rscript": "r",

    # --- Julia ---
    "julia": "julia",
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def resolve_filetype(
    file_path: str | Path,
    vim_filetype: str | None = None,
) -> Optional[str]:
    """Resolve a file path to its canonical filetype.

    Three-layer resolution:
    1. Extension → filetype mapping
    2. Explicit filename lookup (for extensionless files)
    3. Shebang parsing (fallback for extensionless files)
    4. vim_filetype fallback (last resort)

    Args:
        file_path: Path to the file.
        vim_filetype: Optional fallback filetype if all else fails.

    Returns:
        Canonical filetype string, or None if unresolvable.
    """
    file_path = Path(file_path)

    # --- Layer 1: Extension mapping ---
    ext = file_path.suffix.lstrip(".").lower()
    if ext:
        filetype = EXTENSION_TO_FILETYPE.get(ext)
        if filetype is not None:
            return filetype
        # Extension exists but isn't mapped → use it as-is (may be indexed
        # under its own name if included in config.include)
        return ext

    # --- Layer 2: Explicit filename lookup ---
    basename = file_path.name
    filetype = FILENAME_TO_FILETYPE.get(basename)
    if filetype is not None:
        return filetype

    # --- Layer 3: Shebang fallback ---
    filetype = _detect_filetype_from_shebang(file_path)
    if filetype is not None:
        return filetype

    # --- Fallback: vim_filetype ---
    if vim_filetype:
        return vim_filetype

    return None


def get_canonical_extensions(filetype: str) -> list[str]:
    """Get all raw extensions that map to a given canonical filetype.

    Args:
        filetype: Canonical filetype name (e.g. "yaml", "shell").

    Returns:
        List of raw extensions (e.g. ["yaml", "yml"]).
    """
    return [
        ext for ext, ft in EXTENSION_TO_FILETYPE.items()
        if ft == filetype
    ]


def get_filetype_for_extension(ext: str) -> Optional[str]:
    """Get the canonical filetype for a raw extension.

    Args:
        ext: Raw extension without leading dot (e.g. "yml").

    Returns:
        Canonical filetype, or the extension itself if no mapping exists.
    """
    ext = ext.lstrip(".").lower()
    return EXTENSION_TO_FILETYPE.get(ext, ext)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

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

    return None


# ---------------------------------------------------------------------------
# Convenience: build reverse mapping
# ---------------------------------------------------------------------------

def get_extensions_for_filetype(filetype: str) -> set[str]:
    """Get all raw extensions that map to a given canonical filetype."""
    return {
        ext for ext, ft in EXTENSION_TO_FILETYPE.items()
        if ft == filetype
    }


# ---------------------------------------------------------------------------
# Default includes — canonical filetypes only
# ---------------------------------------------------------------------------

DEFAULT_INCLUDES: list[str] = [
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
    "shell",

    # --- Build / Config ---
    "make",
    "docker",
    "hcl",

    # --- Misc ---
    "diff",
    "text",
]
