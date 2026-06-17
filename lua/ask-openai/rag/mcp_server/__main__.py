"""MCP server for semantic_grep queries.

Wraps existing rag/semantic_grep functionality in an MCP tool so it can be
called from any MCP client (not just inside neovim).
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sys
from pathlib import Path
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool
from rich.console import Console
from rich.logging import RichHandler

_xdg_state = Path(
    os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
)
_log_dir = _xdg_state / "mcp-servers"
_log_dir.mkdir(parents=True, exist_ok=True)

_log_file = open(_log_dir / "semantic-grep.log", "a")
_console = Console(file=_log_file, force_terminal=True, width=150, tab_size=4)

_rich_handler = RichHandler(
    markup=True,
    rich_tracebacks=True,
    console=_console,
    show_path=False,
    show_time=False,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s: %(message)s",
    datefmt="[%X]",
    handlers=[_rich_handler],
    force=True,
)

# path setup — add rag root to sys.path so lsp.* imports resolve
_RAG_ROOT = Path(__file__).resolve().parent.parent
if str(_RAG_ROOT) not in sys.path:
    sys.path.insert(0, str(_RAG_ROOT))

from index.storage import Datasets, load_all_datasets
from inference.client.retrieval import (
    LSPRankedMatch,
    LSPSemanticGrepRequest,
    semantic_grep as _semantic_grep,
)
from index import workspace
from logs import get_logger

logger: logging.Logger = get_logger(__name__)
# logging.getLogger("mcp").setLevel(logging.DEBUG)  # MCP SDK logs

_datasets: Datasets | None = None

def _get_datasets() -> Datasets:
    """Return loaded datasets, raising if they haven't been initialized."""
    global _datasets
    if _datasets is None:
        raise RuntimeError("Datasets not initialized — is the server started with a valid root_dir?")
    return _datasets


SEMANTIC_GREP_TOOL = Tool(
    name="semantic_grep",
    description=(
        "Search codebase embeddings for semantically relevant code chunks. "
        "Returns ranked matches with file paths, line numbers, and content."
    ),
    inputSchema={
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "The natural-language or keyword query to search for.",
            },
            "current_file_absolute_path": {
                "type": "string",
                "description": (
                    "Absolute path of the current file (used to determine which language "
                    "dataset to search). Pass empty string or omit for global search."
                ),
            },
            "vim_filetype": {
                "type": "string",
                "description": (
                    "Vim filetype fallback when current_file_absolute_path is not provided "
                    "(e.g. 'lua', 'py', 'ts')."
                ),
            },
            "languages": {
                "type": "string",
                "enum": ["GLOBAL", "EVERYTHING"],
                "description": (
                    "Search scope. 'GLOBAL' searches only configured global_languages from "
                    "rag.yaml. 'EVERYTHING' searches all indexed languages."
                ),
            },
            "skip_same_file": {
                "type": "boolean",
                "description": "When true, exclude matches from the same file as current_file_absolute_path.",
            },
            "top_k": {
                "type": "integer",
                "description": "Number of final results to return after reranking. Default: 5.",
            },
            "embed_top_k": {
                "type": "integer",
                "description": (
                    "Number of candidate chunks to retrieve before reranking. "
                    "Defaults to top_k if not specified."
                ),
            },
            "instruct": {
                "type": "string",
                "description": (
                    "Instructions for the embedding/reranker model. Must be specific to the "
                    "query type — this is required."
                ),
            },
        },
        "required": ["query", "instruct"],
    },
)


def _match_to_text_content(match: LSPRankedMatch) -> dict[str, Any]:
    """Convert a LSPRankedMatch into a serializable dict for MCP TextContent."""
    file_rel = workspace.relative_to_workspace(match.file) # TODO rename workspace.relative_path(what)?
    file_path = match.file  # absolute path

    return {
        "id": match.id,
        "rerank_rank": match.rerank_rank,
        "rerank_score": match.rerank_score,
        "embed_score": match.embed_score,
        "embed_rank": match.embed_rank,
        "file": file_path,
        "file_relative": str(file_rel),
        "start_line": match.start_line_base0 + 1,
        "end_line": match.end_line_base0 + 1,
        "signature": match.signature,
        "type": match.type,
        "text": match.text,
    }


async def handle_semantic_grep(
    query: str,
    current_file_absolute_path: str | None = None,
    vim_filetype: str | None = None,
    languages: str = "",
    skip_same_file: bool = False,
    top_k: int = 5,
    embed_top_k: int | None = None,
    instruct: str | None = None,
) -> list[TextContent]:
    """Execute a semantic_grep query and return formatted results."""
    # Validate inputs
    if not query or len(query) == 0:
        raise ValueError("query is required and cannot be empty")

    if not instruct:
        raise ValueError("instruct is required — must be specific to the query type")

    if languages not in ("", "GLOBAL", "EVERYTHING"):
        raise ValueError(f"languages must be one of: '', 'GLOBAL', 'EVERYTHING', got '{languages}'")

    if top_k < 1:
        raise ValueError("top_k must be >= 1")

    datasets = _get_datasets()

    # Build the request object using existing types
    request = LSPSemanticGrepRequest(
        query=query,
        currentFileAbsolutePath=current_file_absolute_path,
        vimFiletype=vim_filetype,
        instruct=instruct,
        skipSameFile=skip_same_file,
        topK=top_k,
        embedTopK=embed_top_k,
        languages=languages,
    )

    # Execute the semantic_grep query (reuse existing function)
    matches: list[LSPRankedMatch] = await _semantic_grep(
        args=request,
        datasets=datasets,
    )

    if not matches:
        return [
            TextContent(
                type="text",
                text="No matches found for the given query.",
            )
        ]

    # Serialize matches
    result_dicts = [_match_to_text_content(m) for m in matches]

    # Format as a single readable response
    output_lines: list[str] = [f"Found {len(matches)} match(es):\n"]
    for match_data in result_dicts:
        output_lines.append(
            f"  [{match_data['rerank_rank']}]"
            f" rerank={match_data['rerank_score']:.4f}"
            f" embed={match_data['embed_score']:.4f}"
            f"  {match_data['file_relative']}"
            f"  L{match_data['start_line']}-{match_data['end_line']}"
            f"\n    {match_data['text'][:200]}"
        )
        output_lines.append("")

    return [TextContent(type="text", text="\n".join(output_lines))]


async def serve(root_dir: str | Path | None = None) -> None:
    """Start the MCP semantic_grep server."""
    server = Server("semantic-grep")

    # * Initialize datasets
    global _datasets
    if root_dir is None:
        # Try to find a .rag dir from CWD
        cwd = Path.cwd()
        if (cwd / ".rag").exists():
            root_dir = cwd
        else:
            raise ValueError(
                "root_dir is required — pass it from the MCP client or run from a workspace with a .rag dir"
            )

    root_dir_path = Path(root_dir)
    await workspace.set_workspace(root_dir_path) # TODO rename set_folder/set_dir()?
    _dot_rag_dir = root_dir_path / ".rag"

    logger.info(f"Loading datasets from {_dot_rag_dir}")
    _datasets = load_all_datasets(_dot_rag_dir)
    logger.info(f"Loaded {_datasets.all_datasets.keys()} datasets")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [SEMANTIC_GREP_TOOL]

    @server.call_tool()
    async def call_tool(requested_tool: str, arguments: dict[str, Any]) -> list[TextContent]:
        try:
            if requested_tool != SEMANTIC_GREP_TOOL.name:
                raise ValueError(
                    f"Unknown tool '{requested_tool}'. Available: {SEMANTIC_GREP_TOOL.name}"
                )

            query: str = arguments.get("query", "")
            current_file_path: str | None = arguments.get("current_file_absolute_path") or None
            vim_filetype: str | None = arguments.get("vim_filetype") or None
            languages: str = arguments.get("languages", "") or ""
            skip_same_file: bool = arguments.get("skip_same_file", False)
            top_k: int = int(arguments.get("top_k", 5))
            embed_top_k: int | None = arguments.get("embed_top_k")
            instruct: str | None = arguments.get("instruct")

            return await handle_semantic_grep(
                query=query,
                current_file_absolute_path=current_file_path,
                vim_filetype=vim_filetype,
                languages=languages,
                skip_same_file=skip_same_file,
                top_k=top_k,
                embed_top_k=embed_top_k,
                instruct=instruct,
            )

        except asyncio.CancelledError:
            logger.info("semantic_grep request was cancelled")
            raise
        except ValueError as error:
            logger.warning(f"Invalid semantic_grep arguments: {error}")
            raise RuntimeError(str(error)) from error
        except Exception as error:
            logger.exception(f"Unexpected error in semantic_grep tool")
            raise RuntimeError(str(error)) from error

    # * Start the server
    options = server.create_initialization_options()
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, options, raise_exceptions=False)


def main() -> None:
    """Entry point — parse root_dir from argv or use CWD."""
    parser = argparse.ArgumentParser(
        description="MCP server for semantic_grep queries"
    )
    parser.add_argument(
        "--root-dir",
        type=str,
        default=None,
        help="Root directory of the workspace containing a .rag directory",
    )
    args = parser.parse_args()

    try:
        asyncio.run(serve(root_dir=args.root_dir))
    except Exception as error:
        logger.exception(f"[bold red]Server error:[/bold red] {error}")
        raise


if __name__ == "__main__":
    # for python3 -m mcp_server
    # entrypoint doesn't use this, b/c it uses importlib (hence why you setup mcp_server.__main__:main to invoke main() there too)
    main()
