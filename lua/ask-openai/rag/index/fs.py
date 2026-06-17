from typing import Optional
import aiofiles
from pathlib import Path

from rag.logs import get_logger
from config import RagConfig, load_config

logger = get_logger(__name__)

class RagProject:
    # this exists to avoid the need for `globals` concerns
    root_path: Optional[Path] = None
    dot_rag_dir: Optional[Path] = None
    config: RagConfig = RagConfig.default()

# *** by the way I am not 100% certain I like this module... but lets see how it goes
#   I need a simple way to get a path relative to the workspace dir
#   without passing that workspace dir everywhere
#   but also don't break passing it when it makes sense b/c then it becomes a hidden dependency
rag_project = RagProject()

def is_no_rag_dir() -> bool:
    if rag_project.dot_rag_dir is None:
        return False
    return not rag_project.dot_rag_dir.exists()

def get_cwd_repo_root() -> Path | None:
    """
    Get the root directory of the current Git repository
    """
    import subprocess
    try:
        root_directory = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
        root_directory = Path(root_directory)
    except subprocess.CalledProcessError:
        root_directory = None
    return root_directory

async def set_root_dir(root_dir: str | Path | None):
    logger.info(f"{root_dir=}")
    rag_project.root_path = Path(root_dir)
    rag_project.dot_rag_dir = rag_project.root_path / ".rag"
    if is_no_rag_dir():
        logger.error(f"abort on_initialize b/c no .rag dir, {rag_project.dot_rag_dir=}")
        # no need to do anything else, the LS server handles setting no capabilities

    logger.debug(f"{rag_project.dot_rag_dir=}")

    await load_rag_config(rag_project.root_path)

async def load_rag_config(root_path: Path) -> RagConfig:
    rag_yaml = root_path / ".rag.yaml"
    if not rag_yaml.exists():
        logger.info(f"no rag config found {rag_yaml}, using default config")
        return RagConfig.default()

    async with aiofiles.open(rag_yaml, mode="r") as f:
        content = await f.read()
    rag_project.config = load_config(content)
    logger.pp_debug(f"found rag config", rag_yaml)
    return rag_project.config

def get_config() -> RagConfig:
    return rag_project.config

def relative_to_workspace(path: Path | str, override_root_path: Path | None = None) -> Path:
    path = Path(path)
    use_root_path = override_root_path or rag_project.root_path

    if use_root_path is None:
        return path

    if not path.is_relative_to(use_root_path):
        return path

    return path.relative_to(use_root_path)

def get_loggable_path(path: Path | str) -> str:
    if not isinstance(path, str):
        path = str(path)
    if rag_project.root_path is None:
        return path
    return f"[bold]{relative_to_workspace(path)}[/bold]"
