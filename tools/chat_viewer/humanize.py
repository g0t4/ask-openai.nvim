from datetime import datetime, timezone
from pathlib import Path


def humanize_size(value: int | Path) -> str:
    """Convert a byte count to a human‑readable string with appropriate units."""
    if isinstance(value, int):
        num_bytes = value
    elif isinstance(value, Path):
        num_bytes = value.stat().st_size
    else:
        raise TypeError("value must be an int or pathlib.Path")

    assert isinstance(num_bytes, (int, float))
    if num_bytes < 0:
        raise ValueError("value must be non‑negative")
    units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
    idx = 0
    while num_bytes >= 1024 and idx < len(units) - 1:
        num_bytes /= 1024.0
        idx += 1
    if num_bytes < 10 and idx > 0:
        formatted = f"{num_bytes:.1f}"
    else:
        formatted = f"{num_bytes:.0f}"
    return f"{formatted} {units[idx]}"


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
