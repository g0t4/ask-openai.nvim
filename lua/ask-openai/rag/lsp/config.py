from dataclasses import dataclass, field
import os

import yaml

# map aliased/alternative extensions to a primary extension
ALIASED_EXTENSIONS: dict[str, str] = {
    # used: preferred
    "yml": "yaml",
}

# TODO I need to create groupings of related extensions... i.e. fish+zsh+bash+sh as 'shell' type
#   TODO! combine alt file extensions that are the same: yaml/yml
#   PRN also use shebang when chunking files? and look at plaintext, extensionless files w/ a shebang (esp chmod +x files)
default_includes: list[str] = [
        "lua", "py", "java", "js", "ts", "html",
        "md", "json", "yaml", "yml",
        "fish", "zsh", "sh", # shells
        "cpp", "cc", "c", "h", "hpp", # c related
        "m", "mm", # objective c
        "cu", "cuh", "cl", # GPU
        "rs",
        "go",
        "patch",
    ] # yapf: disable

default_ignores: list[str] = []
default_global_languages: list[str] = []  # no defaults b/c if you don't set it, you get all indexed file types (includes)
default_enabled: bool = True

@dataclass
class Config:
    ignores: list[str] = field(default_factory=list)
    include: list[str] = field(default_factory=list)
    global_languages: list[str] = field(default_factory=list)
    enabled: bool = field(default=default_enabled)

    @staticmethod
    def default() -> "Config":
        return Config(
            include=default_includes,
            ignores=default_ignores,
            global_languages=default_global_languages,
            enabled=default_enabled,
        )

    def is_file_type_supported(self, doc_path: str) -> bool:
        _, ext = os.path.splitext(doc_path)
        file_type = ext.lstrip('.').lower()

        # TODO is this file extension or was filetype vim filetype? if so you'll have to use a lookup!
        #   FYI can fix that later, just get this started for now so I don't log false positives in LSP server for Unsupported files (most of the time anyways)

        file_type = ALIASED_EXTENSIONS.get(file_type, file_type)

        return file_type in self.include
        # and (file_type not in self.ignores) # TODO ignores need a method that does the match check

def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else default_enabled

    return Config(
        ignores=raw.get("ignores") or default_ignores,
        include=raw.get("include") or default_includes,
        global_languages=raw.get("global_languages") or default_global_languages,
        enabled=_enabled,
    )
