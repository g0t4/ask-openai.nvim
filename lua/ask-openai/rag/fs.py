from pathlib import Path

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
