from dataclasses import dataclass, field
import os
from pathlib import Path

import yaml

from lsp.filetypes import (
    DEFAULT_INCLUDED_FILETYPES,
    EXTENSION_TO_FILETYPE,
    BASENAME_TO_FILETYPE,
    resolve_filetype,
)


default_ignores: set[str] = set()
default_global_languages: set[str] = set()  # no defaults b/c if you don't set it, you get all indexed file types (includes)
DEFAULT_RAG_ENABLED: bool = True

from lsp.logs import get_logger
logger = get_logger(__name__)

def _map_included_file_extensions_to_filetypes(raw_includes: set[str]) -> set[str]:
    """Normalize include list: convert raw extensions to canonical filetypes.

    Handles both old-style raw extensions (js, ts, yml, fish) and
    new-style canonical filetypes (javascript, typescript, yaml, shell).
    Unmapped extensions pass through as-is. Deduplicates results.
    """
    # include is inteded as extensions/filetypes... so map extensions to filetypes too...
    # PRN rename to include_filetypes or smth else to convey post extensions design?
    filetypes = [resolve_filetype("." + item) or item for item in raw_includes]
    return set(filetypes)


@dataclass
class Config:
    ignores: set[str] = field(default_factory=set)
    #
    # included filetypes (ideally, or extension which is mapped to filetype)
    included_filetypes: set[str] = field(default_factory=set)
    #
    global_filetypes: set[str] = field(default_factory=set)
    #
    enabled: bool = field(default=DEFAULT_RAG_ENABLED)

    @staticmethod
    def default() -> "Config":
        return Config(
            included_filetypes=DEFAULT_INCLUDED_FILETYPES,
            ignores=default_ignores,
            global_filetypes=default_global_languages,
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
        return filetype in self.included_filetypes


def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else DEFAULT_RAG_ENABLED
    _include = raw.get("include_filetypes") or raw.get("include") or DEFAULT_INCLUDED_FILETYPES
    _include = _map_included_file_extensions_to_filetypes(_include)

    if raw.get("include"):
        logger.error("include is deprecated; use include_filetypes instead")
        raise ValueError("include is deprecated; use include_filetypes instead")

    if raw.get("global_languages"):
        logger.error("global_languages is deprecated; use global_filetypes instead")
        raise ValueError("global_languages is deprecated; use global_filetypes instead")

    global_filetypes = raw.get("global_filetypes") or raw.get("global_languages") or default_global_languages
    return Config(
        ignores=raw.get("ignores") or default_ignores,
        included_filetypes=_include,
        global_filetypes=global_filetypes,
        enabled=_enabled,
    )
