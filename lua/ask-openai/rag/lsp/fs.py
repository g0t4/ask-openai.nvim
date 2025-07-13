from pathlib import Path

root_path: Path | None = None

def set_root_dir(dir: Path | None):
    global root_path
    root_path = dir

def relative_to_workspace(path: Path | str) -> Path:
    path = Path(path)

    if root_path is None:
        return path

    if not path.is_relative_to(root_path):
        return path

    return path.relative_to(root_path)
