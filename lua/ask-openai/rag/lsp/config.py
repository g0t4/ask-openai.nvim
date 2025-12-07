import yaml

from dataclasses import dataclass, field

default_includes: list[str] = ["lua", "py", "fish"]
default_ignores: list[str] = []
default_global_languages: list[str] = []
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
