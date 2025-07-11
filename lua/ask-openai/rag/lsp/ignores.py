from pathlib import Path

from pathspec import PathSpec
from pathspec.patterns.gitwildmatch import GitWildMatchPattern
from rich import print

from lsp.logs import get_logger

logger = get_logger(__name__)

spec: PathSpec | None = None
root_path: Path | None = None

def use_pygls_workspace(root_path_input: str | Path):
    global spec, root_path
    root_path = Path(root_path_input)
    spec = use_gitignore(root_path)
    # PRN other gitignore logic? other ignore file types?

def use_gitignore(root_path: Path | str) -> PathSpec:
    root_path = Path(root_path)
    gitignore_path = root_path.joinpath(".gitignore")

    ignore_entries = set()
    if gitignore_path.exists():
        ignore_entries = set(gitignore_path.read_text().splitlines())

    # ALWAYS exclude:
    ignore_entries.update([
        # focus on directories mostly, the languages you actually index can filter on file types implicitly (not indexed == ignored too)
        ".git",
        ".venv",
        "__pycache__",
        "node_modules",
        "bower_components",
        "iterm2env",
    ])

    return PathSpec.from_lines(GitWildMatchPattern, ignore_entries)

warned_missing_spec = False

def is_ignored(file_path: str | Path):
    file_path = Path(file_path)
    global warned_missing_spec  # FYI put globals at top to make it clear they apply to entire code block / scope

    if spec is None or root_path is None:
        if not warned_missing_spec:
            # TODO send custom notification workspace/configIssue or otherwise, setup client to alert user
            logger.error("No gitignore spec setup, allowing all files!")
            warned_missing_spec = True
        return False

    if not file_path.is_relative_to(root_path):
        # FYI for now IGNORE all files NOT inside the root path
        return True

    # relative path is needed for relative patterns that start without a wildcard
    rel_path = file_path.relative_to(root_path)

    return spec.match_file(rel_path)
