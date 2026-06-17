import aiofiles
import subprocess
import sys
from dataclasses import field
from pathlib import Path
from typing import Optional

from logs import get_logger
from config import RagConfig, load_config
from index.storage import Datasets, load_all_datasets
from index.validate import DatasetsValidator

logger = get_logger(__name__)

class RagProject:
    # this exists to avoid the need for `globals` concerns
    folder: Path = field(default_factory=Path)
    dot_rag_dir: Path = field(default_factory=Path)
    config: RagConfig = RagConfig.default()

# *** by the way I am not 100% certain I like this module... but lets see how it goes
#   I need a simple way to get a path relative to the workspace dir
#   without passing that workspace dir everywhere
#   but also don't break passing it when it makes sense b/c then it becomes a hidden dependency
project = RagProject()
# TODO expand project again to be globals here? or more datasets onto project?
datasets: Datasets = None

def is_no_rag_dir() -> bool:
    if project.dot_rag_dir is None:
        return False
    return not project.dot_rag_dir.exists()

def _git_repo_root_dir(from_dir: str | Path) -> Path | None:
    try:
        argv = ["git", "-C", from_dir, "rev-parse", "--show-toplevel"]
        root_directory = subprocess.check_output(argv, text=True).strip()
        root_directory = Path(root_directory)
    except subprocess.CalledProcessError:
        root_directory = None
    return root_directory

async def from_repo_root(any_path_in_repo: str | Path):
    """ common strategy:
    folder = repo_root
    dot_rag_dir = repo_root/.rag/
    """
    repo_root_dir = _git_repo_root_dir(any_path_in_repo)
    if repo_root_dir is None:
        logger.error(f"[red]{any_path_in_repo} is not in a git repo")
        sys.exit(1)
    await from_folder(repo_root_dir)

async def from_workdir_in_repo():
    """
    folder == workdir (aka PWD)
    dot_rag_dir == workdir's git repo root dir

    FYI IF workder != repo_root_dir THEN workspace_dir/.rag != dot_rag_dir
    """
    repo_root_dir = _git_repo_root_dir(Path.cwd())
    if repo_root_dir is None:
        logger.error("[red]No Git repository found in current working directory, cannot build RAG index.")
        sys.exit(1)
    project.folder = Path(".").resolve()
    project.dot_rag_dir = repo_root_dir / ".rag"
    logger.info(f"[bold]RAG directory: {project.dot_rag_dir}")

    await load_rag_config(project.folder)

async def from_folder(folder: str | Path):
    """
    folder = folder
    dot_rag_dir = folder/.rag/
    """
    logger.info(f"{folder=}")
    project.folder = Path(folder)
    project.dot_rag_dir = project.folder / ".rag"
    if is_no_rag_dir():
        logger.error(f"abort on_initialize b/c no .rag dir, {project.dot_rag_dir=}")
        # no need to do anything else, the LS server handles setting no capabilities

    logger.debug(f"{project.dot_rag_dir=}")

    await load_rag_config(project.folder)

    global datasets
    datasets = load_all_datasets(project.dot_rag_dir)

async def load_rag_config(root_path: Path) -> RagConfig:
    rag_yaml = root_path / ".rag.yaml"
    if not rag_yaml.exists():
        logger.info(f"no rag config found {rag_yaml}, using default config")
        return RagConfig.default()

    async with aiofiles.open(rag_yaml, mode="r") as f:
        content = await f.read()
    project.config = load_config(content)
    logger.pp_debug(f"found rag config", rag_yaml)
    return project.config

def get_config() -> RagConfig:
    return project.config

def get_relative_path_to(path: Path | str, override_root_path: Path | None = None) -> Path:
    path = Path(path)
    use_root_path = override_root_path or project.folder

    if use_root_path is None:
        return path

    if not path.is_relative_to(use_root_path):
        return path

    return path.relative_to(use_root_path)

def validate_datasets():
    if datasets is None:
        raise RuntimeError("cannot validate datasets because datasets are not yet loaded!")

    validator = DatasetsValidator(datasets)
    validator.validate_datasets()
