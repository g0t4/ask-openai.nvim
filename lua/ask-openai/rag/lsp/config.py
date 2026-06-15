from dataclasses import dataclass, field
import os
from pathlib import Path

import yaml

from lsp.filetypes import (
    DEFAULT_INCLUDES,
    EXTENSION_TO_FILETYPE,
    FILENAME_TO_FILETYPE,
    get_filetype_for_extension,
    resolve_filetype,
)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

default_ignores: list[str] = []
default_global_languages: list[str] = []  # no defaults b/c if you don't set it, you get all indexed file types (includes)
default_enabled: bool = True


def _include_filetypes(raw_includes: list[str]) -> list[str]:
    """Normalize include list: convert raw extensions to canonical filetypes.

    Handles both old-style raw extensions (js, ts, yml, fish) and
    new-style canonical filetypes (javascript, typescript, yaml, shell).
    Unmapped extensions pass through as-is. Deduplicates results.
    """
    normalized = [get_filetype_for_extension(item) or item for item in raw_includes]
    return list(set(normalized))


@dataclass
class Config:
    ignores: list[str] = field(default_factory=list)
    include: list[str] = field(default_factory=list)
    global_languages: list[str] = field(default_factory=default_global_languages)
    enabled: bool = field(default=default_enabled)

    @staticmethod
    def default() -> "Config":
        return Config(
            include=DEFAULT_INCLUDES,
            ignores=default_ignores,
            global_languages=default_global_languages,
            enabled=default_enabled,
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

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else default_enabled
    _include = raw.get("include") or DEFAULT_INCLUDES
    # Normalize: convert raw extensions (js, ts, yml, fish) to canonical filetypes
    _include = _include_filetypes(_include)

    return Config(
        ignores=raw.get("ignores") or default_ignores,
        include=_include,
        global_languages=raw.get("global_languages") or default_global_languages,
        enabled=_enabled,
    )
