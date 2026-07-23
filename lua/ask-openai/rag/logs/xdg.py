from pathlib import Path
import os


def XDG_DATA_HOME():
    return Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")))


def XDG_STATE_HOME():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state")))
