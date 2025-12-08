import yaml

from dataclasses import dataclass, field

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

def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    _enabled = raw.get("enabled") if raw.get("enabled") is not None else default_enabled

    return Config(
        ignores=raw.get("ignores") or default_ignores,
        include=raw.get("include") or default_includes,
        global_languages=raw.get("global_languages") or default_global_languages,
        enabled=_enabled,
    )
