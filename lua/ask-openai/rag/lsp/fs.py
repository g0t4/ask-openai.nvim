from dataclasses import dataclass, field
from typing import Optional
import aiofiles
from pathlib import Path

import yaml
from .logs import get_logger

logger = get_logger(__name__)

@dataclass
class Config:
    ignores: list[str] = field(default_factory=list)
    include: list[str] = field(default_factory=list)
    global_languages: list[str] = field(default_factory=list)

    @staticmethod
    def default() -> "Config":
        return Config(
            include=["lua", "py", "fish"],  #
        )

def load_config(yaml_text: str) -> Config:
    raw = yaml.safe_load(yaml_text)

    return Config(
        ignores=raw.get("ignores") or [],
        include=raw.get("include") or [],
        global_languages=raw.get("global_languages") or [],
    )

root_path: Path | None = None
dot_rag_dir: Path | None = None
config: Config = Config.default()

# *** by the way I am not 100% certain I like this module... but lets see how it goes
#   I need a simple way to get a path relative to the workspace dir
#   without passing that workspace dir everywhere
#   but also don't break passing it when it makes sense b/c then it becomes a hidden dependency

def is_no_rag_dir() -> bool:
    if dot_rag_dir is None:
        return False
    return not dot_rag_dir.exists()

def set_root_dir(root_dir: str | Path | None):
    global root_path, dot_rag_dir, config

    if root_dir is None:
        logger.error(f"aborting on_initialize b/c missing client workspace dir, {root_dir=}")
        raise ValueError("root_uri is None")

    root_path = Path(root_dir)
    logger.debug(f"{root_path=}")

    dot_rag_dir = Path(root_path) / ".rag"
    if is_no_rag_dir():
        logger.error(f"abort on_initialize b/c no .rag dir, {dot_rag_dir=}")
        # no need to do anything else, the LS server handles setting no capabilities

    logger.debug(f"{dot_rag_dir=}")

    # * config
    rag_yaml = root_path / ".rag.yaml"
    if rag_yaml.exists():
        config = load_config(rag_yaml.read_text())
        logger.pp_debug(f"found rag config: {rag_yaml}", config)
    else:
        logger.info(f"no rag config found {rag_yaml}, using default config")
        config = Config.default()

def get_config():
    return config

def relative_to_workspace(path: Path | str) -> Path:
    path = Path(path)

    if root_path is None:
        return path

    if not path.is_relative_to(root_path):
        return path

    return path.relative_to(root_path)

def get_loggable_path(path: Path | str) -> str:
    if not isinstance(path, str):
        path = str(path)
    if root_path is None:
        return path
    return f"[bold]{relative_to_workspace(path)}[/bold]"

def read_text_lines(path: Path, encoding="utf-8") -> list[str]:
    with open(path, "r", encoding=encoding) as f:
        return f.readlines()

def read_bytes_lines(path: Path) -> list[bytes]:
    with open(path, "rb") as f:
        return f.readlines()

# TODO unused for sync below b/c I found path.read_text() exists
#    but now that I want some async file ops... might be useful to revisit this helper as async.
#    read_text(path) is a nice wrapper

async def read_text(path: Path, encoding="utf-8") -> str:
    async with aiofiles.open(path, "r", encoding=encoding) as f:
        return await f.read()

def read_bytes(path: Path) -> bytes:
    with open(path, "rb") as f:
        return f.read()
