from pathlib import Path
from .logs import get_logger

logger = get_logger(__name__)

root_path: Path
dot_rag_dir: Path

# *** by the way I am not 100% certain I like this module... but lets see how it goes
#   I need a simple way to get a path relative to the workspace dir
#   without passing that workspace dir everywhere
#   but also don't break passing it when it makes sense b/c then it becomes a hidden dependency

def is_no_rag_dir() -> bool:
    if dot_rag_dir is None:
        return False
    return not dot_rag_dir.exists()

def set_root_dir(root: str | None):
    global root_path, dot_rag_dir

    if root is None:
        logger.error(f"aborting on_initialize b/c missing client workspace dir, {root=}")
        raise ValueError("root_uri is None")

    root_path = Path(root)
    logger.debug(f"{root_path=}")

    dot_rag_dir = Path(root_path) / ".rag"
    if is_no_rag_dir():
        logger.error(f"abort on_initialize b/c no .rag dir, {dot_rag_dir=}")
        raise RuntimeError("client does not have .rag dir")

    logger.debug(f"{dot_rag_dir=}")

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
