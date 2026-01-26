from pathlib import Path

from pathspec import PathSpec
from pathspec.patterns.gitwildmatch import GitWildMatchPattern

from lsp.logs import get_logger
from lsp.config import Config
from lsp import fs

logger = get_logger(__name__)

# don't mark None by default, else pyright will be a PITA
gitignore_spec: PathSpec

def setup_ignores():
    global gitignore_spec

    def _setup_gitignored() -> PathSpec:
        # TODO why not just create this on first use! have helper to create/get it
        #   TODO then I can clean up mess of using fs module for root_path etc
        gitignore_path = fs.root_path.joinpath(".gitignore")
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

            # files that are often committed but shouldn't ever be indexed:
            "package-lock.json",
            "uv.lock",  # PRN *.lock?
            # ? other lock files?
        ])

        return PathSpec.from_lines(GitWildMatchPattern, ignore_entries)

    gitignore_spec = _setup_gitignored()
    # TODO separate spec for config.ignores, OR, merge into gitignore_spec?

IGNORED = True

def is_ignored_allchecks(file_path: str | Path, config: Config):
    """ unified ignore checks """
    # TODO wire this into rag_validate_index

    file_path = Path(file_path)
    if not config.is_file_type_supported(file_path):
        logger.debug(f"filetype not supported: {file_path}")
        return IGNORED

    if _is_gitignored(file_path):
        return IGNORED

    # fallback, assume allowed
    return not IGNORED

def _is_gitignored(file_path: str | Path):
    """ only ignores for gitignore """
    file_path = Path(file_path)

    if not file_path.is_relative_to(fs.root_path):
        # FYI for now IGNORE all files NOT inside the root path
        return IGNORED

    # relative path is needed for relative patterns that start without a wildcard
    rel_path = file_path.relative_to(fs.root_path)

    return gitignore_spec.match_file(rel_path)
