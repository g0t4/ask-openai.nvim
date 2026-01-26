from pathlib import Path

from pathspec import PathSpec
from pathspec.patterns.gitwildmatch import GitWildMatchPattern

from lsp.logs import get_logger
from lsp.config import Config

logger = get_logger(__name__)

def setup_ignores(fs_root_path) -> PathSpec:
    # TODO why not just create this on first use! have helper to create/get it
    gitignore_path = fs_root_path.joinpath(".gitignore")

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

        # files that are often committed but shouldn't ever be indexed:
        "package-lock.json",
        "uv.lock",  # PRN *.lock?
        # ? other lock files?
    ])
    # TODO config.ignores load into gitignore spec!

    return PathSpec.from_lines(GitWildMatchPattern, ignore_entries)

gitignore_spec: PathSpec = None

def get_gitignore_spec(fs_root_path):
    global gitignore_spec
    # FYI always the same, so cache it... TECHNICALLY I SHOULD CACHE PER PATH
    # TODO memoize the function

    if (gitignore_spec is None):
        gitignore_spec = setup_ignores(fs_root_path)

    return gitignore_spec

IGNORED = True

def is_ignored_allchecks(file_path: str | Path, config: Config, fs_root_path: Path):
    """ unified ignore checks """
    # TODO wire this into rag_validate_index

    file_path = Path(file_path)
    if not config.is_file_type_supported(file_path):
        logger.debug(f"filetype not supported: {file_path}")
        return IGNORED

    if _is_gitignored(file_path, fs_root_path):
        return IGNORED

    # fallback, assume allowed
    return not IGNORED

def _is_gitignored(file_path: str | Path, fs_root_path):
    """ only ignores for gitignore """
    file_path = Path(file_path)

    if not file_path.is_relative_to(fs_root_path):
        # FYI for now IGNORE all files NOT inside the root path
        return IGNORED

    # relative path is needed for relative patterns that start without a wildcard
    rel_path = file_path.relative_to(fs_root_path)

    spec = get_gitignore_spec(fs_root_path)
    return spec.match_file(rel_path)
