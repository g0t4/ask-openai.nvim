from pathlib import Path
from datetime import datetime, timezone


def file_age(path: Path):
    # proxy of information w/o loading contents
    if path.name.endswith("-trace.json"):
        # FYI we should probably use created timestamp here too... hrm
        ts = datetime.fromtimestamp(int(path.stem.split("-")[0]))
    else:
        # use the file's created timestamp (i.e. for *.jsonl)
        ts = datetime.fromtimestamp(path.stat().st_ctime, tz=timezone.utc)
    relative = relative_age(ts)
    return relative, ts


def relative_age(past: datetime) -> str:
    """Return a human‑readable relative age like “2 days ago”. """
    now = datetime.now(timezone.utc)
    delta = now - past.astimezone(timezone.utc)

    seconds = int(delta.total_seconds())
    minutes = seconds // 60
    hours = minutes // 60
    days = hours // 24

    if days >= 7:
        weeks = days // 7
        return f"{weeks} week{'s' if weeks != 1 else ''} ago"
    if days > 0:
        return f"{days} day{'s' if days != 1 else ''} ago"
    if hours > 0:
        return f"{hours} hour{'s' if hours != 1 else ''} ago"
    if minutes > 0:
        return f"{minutes} minute{'s' if minutes != 1 else ''} ago"
    return f"{seconds} second{'s' if seconds != 1 else ''} ago"
