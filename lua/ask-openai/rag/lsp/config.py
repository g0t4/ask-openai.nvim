from dataclasses import dataclass, field
import os
from pathlib import Path

import yaml

from lsp.filetypes import (
    DEFAULT_INCLUDED_FILETYPES,
    EXTENSION_TO_FILETYPE,
    FILENAME_TO_FILETYPE,
    get_filetype_for_extension,
    resolve_filetype,
)


default_ignores: set[str] = set()
default_global_languages: set[str] = set()  # no defaults b/c if you don't set it, you get all indexed file types (includes)
DEFAULT_RAG_ENABLED: bool = True


def _map_includes_to_filetypes(raw_includes: set[str]) -> set[str]:
    """Normalize include list: convert raw extensions to canonical filetypes.

    Handles both old-style raw extensions (js, ts, yml, fish) and
    new-style canonical filetypes (javascript, typescript, yaml, shell).
    Unmapped extensions pass through as-is. Deduplicates results.
    """
    filetypes = [get_filetype_for_extension(item) or item for item in raw_includes]
    return set(filetypes)


@dataclass
class Config:
    ignores: set[str] = field(default_factory=set)
    #
    # included filetypes (ideally, or extension which is mapped to filetype)
    include: set[str] = field(default_factory=set)
    #
    # TODO rename global_filetypes?  this is for searching only to search across all of these if not searching for a given filetype
    global_languages: set[str] = field(default_factory=set)
    #
    enabled: bool = field(default=DEFAULT_RAG_ENABLED)

    @staticmethod
    def default() -> "Config":
        return Config(
            include=DEFAULT_INCLUDED_FILETYPES,
            ignores=default_ignores,
            global_languages=default_global_languages,
            enabled=DEFAULT_RAG_ENABLED,
        )

    def is_file_type_supported(self, file_path: Path) -> bool:
        """Check if a file's resolved filetype is in the include list.

        Uses the three-layer filetype mapper (extension → filename → shebang)
        to resolve the canonical filetype, then checks against config.include.
        """
        filetype = resolve_filetype(file_path)
        if filetype is None:
            return False
        return filetype in self.include


def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else DEFAULT_RAG_ENABLED
    _include = raw.get("include") or DEFAULT_INCLUDED_FILETYPES
    _include = _map_includes_to_filetypes(_include)

    return Config(
        ignores=raw.get("ignores") or default_ignores,
        include=_include,
        global_languages=raw.get("global_languages") or default_global_languages,
        enabled=_enabled,
    )
