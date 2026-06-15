from dataclasses import dataclass, field
import os
from pathlib import Path

import yaml

from lsp.domains import (
    DEFAULT_INCLUDED_SEMANTIC_DOMAINS,
    EXTENSION_TO_SEMANTIC_DOMAIN,
    BASENAME_TO_SEMANTIC_DOMAIN,
    resolve_semantic_domain,
)

DEFAULT_IGNORES: set[str] = set()
DEFAULT_GLOBAL_DOMAINS: set[str] = set()  # no defaults b/c if you don't set it, you get all indexed file types (includes)
DEFAULT_RAG_ENABLED: bool = True

from lsp.logs import get_logger

logger = get_logger(__name__)

def _map_included_file_extensions_to_semantic_domains(raw_includes: set[str]) -> set[str]:
    """Normalize include list: convert raw extensions to semantic domains.

    Handles both old-style raw extensions (js, ts, yml, fish) and
    new-style semantic domains (javascript, typescript, yaml, shell).
    """
    domains = [resolve_semantic_domain("." + item) or item for item in raw_includes]
    return set(domains)

@dataclass
class Config:
    ignores: set[str] = field(default_factory=set)
    included_semantic_domains: set[str] = field(default_factory=set)
    global_query_domains: set[str] = field(default_factory=set)
    enabled: bool = field(default=DEFAULT_RAG_ENABLED)

    @staticmethod
    def default() -> "Config":
        return Config(
            included_semantic_domains=DEFAULT_INCLUDED_SEMANTIC_DOMAINS,
            ignores=DEFAULT_IGNORES,
            global_query_domains=DEFAULT_GLOBAL_DOMAINS,
            enabled=DEFAULT_RAG_ENABLED,
        )

    def is_semantic_domain_supported(self, file_path: Path) -> bool:
        domain = resolve_semantic_domain(file_path)
        if domain is None:
            return False
        return domain in self.included_semantic_domains

def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else DEFAULT_RAG_ENABLED
    _include = raw.get("include_domains") or DEFAULT_INCLUDED_SEMANTIC_DOMAINS
    _include = _map_included_file_extensions_to_semantic_domains(_include)

    if raw.get("include") or raw.get("include_filetypes"):
        logger.error("include/include_filetypes is deprecated; use include_domains instead")
        # raise ValueError("include/include_filetypes is deprecated; use include_domains instead")

    if raw.get("global_languages") or raw.get("global_filetypes"):
        logger.error("global_languages/global_filetypes is deprecated; use global_domains instead")
        # raise ValueError("global_languages/global_filetypes is deprecated; use global_domains instead")

    global_domains = raw.get("global_domains") or DEFAULT_GLOBAL_DOMAINS
    return Config(
        ignores=raw.get("ignores") or DEFAULT_IGNORES,
        included_semantic_domains=_include,
        global_query_domains=global_domains,
        enabled=_enabled,
    )
