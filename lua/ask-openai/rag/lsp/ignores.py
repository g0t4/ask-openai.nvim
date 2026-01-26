from pathlib import Path

from pathspec import PathSpec
from pathspec.patterns.gitwildmatch import GitWildMatchPattern

from lsp.logs import get_logger
from lsp.config import Config

logger = get_logger(__name__)

gitignore_spec: PathSpec | None = None
root_path: Path | None = None

def setup_config(root_path_input: str | Path, config: Config):
    global gitignore_spec, root_path
    root_path = Path(root_path_input)

    def _setup_gitignored(root_path: Path | str) -> PathSpec:
        gitignore_path = root_path.joinpath(".gitignore")
        # TODO config.ignores load it into gitignore spec!

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
            # "package-lock.json" # TODO test this and add in
        ])

        return PathSpec.from_lines(GitWildMatchPattern, ignore_entries)

    gitignore_spec = _setup_gitignored(root_path)
    # TODO separate spec for config.ignores, OR, merge into gitignore_spec?

def is_ignored_allchecks(file_path: str | Path, config: Config):
    """ unified ignore checks """
    # TODO wire this into rag_indexer
    # TODO wire this into rag_validate_index

    file_path = Path(file_path)
    if not config.is_file_type_supported(file_path):
        logger.debug(f"filetype not supported: {file_path}")
        return True

    if _is_gitignored(file_path):
        return True

    # fallback, assume allowed
    return False

def _is_gitignored(file_path: str | Path):
    """ only ignores for gitignore """
    file_path = Path(file_path)

    if not file_path.is_relative_to(root_path):
        # FYI for now IGNORE all files NOT inside the root path
        return True

    # relative path is needed for relative patterns that start without a wildcard
    rel_path = file_path.relative_to(root_path)

    return gitignore_spec.match_file(rel_path)
