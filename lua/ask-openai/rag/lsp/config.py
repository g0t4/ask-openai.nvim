from dataclasses import dataclass, field
import os
from pathlib import Path

import yaml

from lsp.domains import (
    DEFAULT_ALLOWED_SEMANTIC_DOMAINS,
    EXTENSION_TO_SEMANTIC_DOMAIN,
    BASENAME_TO_SEMANTIC_DOMAIN,
    resolve_semantic_domain,
)

DEFAULT_IGNORES: set[str] = set()
DEFAULT_GLOBAL_DOMAINS: set[str] = set()  # no defaults b/c if you don't set it, you get all indexed file types (includes)
DEFAULT_RAG_ENABLED: bool = True

from lsp.logs import get_logger

logger = get_logger(__name__)

def _map_allowed_file_extensions_to_semantic_domains(raw_includes: set[str]) -> set[str]:
    """
    Each item in raw_includes is either a file extension (legacy config) or a semantic domain...
    - Map extensions to semantic domains so we can operate purely in terms of semantic domains elsewhere

    This is not some legacy hack/conversion... no, it is also useful to specify a file extension and not worry about what the exact domain is...
    - i.e. I know `.rs` is rust... so why bother remembering if I set `rust` or `rs` for the semantic domain's name?
        also why need to set all the extensions for a domain... domain automatically includes all relevant extensions (and other factors)
      in fact, if I use extensions, I can change the domain names and not need to update any config files
      file extension is definitley a more stable interface!
    """
    domains_from_extensions: set[str] = set()
    verbatim_domains: set[str] = set()

    for include in raw_includes:
        # bypass resolver b/c we only map extension to domain
        if include in EXTENSION_TO_SEMANTIC_DOMAIN:
            # btw this assumes you don't criss-cross extensions and domains...
            # IOTW if there's a mapping then it's an extension
            # and you wouldn't have a domain match an extension that maps to a different domain
            # say...
            #   extension .foo => foobar
            #   extension .baz => foo
            #   here we have an indeterminent case b/c the extension matches a different domain (do not do that!)
            domain = EXTENSION_TO_SEMANTIC_DOMAIN[include]
            domains_from_extensions.add(domain)
        else:
            # assume it is a domain if no extension
            verbatim_domains.add(include)

    unified_domains = domains_from_extensions | verbatim_domains
    logger.info(f"Domains from extensions: {sorted(domains_from_extensions)}")
    logger.info(f"Verbatim domains: {sorted(verbatim_domains)}")
    return unified_domains

@dataclass
class RagConfig:
    ignores: set[str] = field(default_factory=set)
    allowed_semantic_domains: set[str] = field(default_factory=set)
    global_query_domains: set[str] = field(default_factory=set)
    enabled: bool = field(default=DEFAULT_RAG_ENABLED)

    @staticmethod
    def default() -> "RagConfig":
        return RagConfig(
            allowed_semantic_domains=DEFAULT_ALLOWED_SEMANTIC_DOMAINS,
            ignores=DEFAULT_IGNORES,
            global_query_domains=DEFAULT_GLOBAL_DOMAINS,
            enabled=DEFAULT_RAG_ENABLED,
        )

    def is_semantic_domain_supported(self, file_path: Path) -> bool:
        domain = resolve_semantic_domain(file_path)
        if domain is None:
            return False
        return domain in self.allowed_semantic_domains

def load_config(yaml_text: str) -> RagConfig:
    raw = yaml.safe_load(yaml_text)

    enabled = raw.get("enabled") if raw.get("enabled") is not None else DEFAULT_RAG_ENABLED
    allowed = raw.get("include_domains") or DEFAULT_ALLOWED_SEMANTIC_DOMAINS
    allowed = _map_allowed_file_extensions_to_semantic_domains(allowed)

    # TODO remove warnings and error once you migrate most of your machines/envs/repos
    if raw.get("include") or raw.get("include_filetypes"):
        logger.error("include/include_filetypes is deprecated; use include_domains instead")
        raise ValueError("include/include_filetypes is deprecated; use include_domains instead")

    if raw.get("global_languages") or raw.get("global_filetypes"):
        logger.error("global_languages/global_filetypes is deprecated; use global_domains instead")
        raise ValueError("global_languages/global_filetypes is deprecated; use global_domains instead")

    global_domains = raw.get("global_domains") or DEFAULT_GLOBAL_DOMAINS
    return RagConfig(
        ignores=raw.get("ignores") or DEFAULT_IGNORES,
        allowed_semantic_domains=allowed,
        global_query_domains=global_domains,
        enabled=enabled,
    )
