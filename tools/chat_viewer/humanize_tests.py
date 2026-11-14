from datetime import datetime, timezone, timedelta
from pathlib import Path
import tempfile
import pytest
from tools.chat_viewer.humanize import relative_age, humanize_size


def test_humanize_size_bytes():
    assert humanize_size(0) == "0 B"
    assert humanize_size(512) == "512 B"
    assert humanize_size(1023) == "1023 B"


def test_humanize_size_kb():
    assert humanize_size(1024) == "1.0 KB"
    assert humanize_size(1536) == "1.5 KB"
    assert humanize_size(10 * 1024) == "10 KB"


def test_humanize_size_mb_gb():
    assert humanize_size(1024**2) == "1.0 MB"
    assert humanize_size(5 * 1024**2) == "5.0 MB"
    assert humanize_size(1024**3) == "1.0 GB"


def test_humanize_size_path():
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(b"a" * 2048)
        fname = f.name
    try:
        p = Path(fname)
        assert humanize_size(p) == "2.0 KB"
    finally:
        Path(fname).unlink()


def test_humanize_size_negative():
    with pytest.raises(ValueError):
        humanize_size(-1)


def test_humanize_size_invalid_type():
    with pytest.raises(TypeError):
        humanize_size("123")


def test_relative_age_seconds():
    now = datetime.now(timezone.utc)
    past = now - timedelta(seconds=42)
    assert relative_age(past) == "42 seconds ago"


def test_relative_age_one_second():
    now = datetime.now(timezone.utc)
    past = now - timedelta(seconds=1)
    assert relative_age(past) == "1 second ago"


def test_relative_age_minutes():
    now = datetime.now(timezone.utc)
    past = now - timedelta(minutes=5)
    assert relative_age(past) == "5 minutes ago"


def test_relative_age_hours():
    now = datetime.now(timezone.utc)
    past = now - timedelta(hours=3)
    assert relative_age(past) == "3 hours ago"


def test_relative_age_days():
    now = datetime.now(timezone.utc)
    past = now - timedelta(days=2)
    assert relative_age(past) == "2 days ago"


def test_relative_age_weeks():
    now = datetime.now(timezone.utc)
    past = now - timedelta(days=14)
    assert relative_age(past) == "2 weeks ago"


def test_relative_age_singular():
    now = datetime.now(timezone.utc)
    past = now - timedelta(days=1)
    assert relative_age(past) == "1 day ago"
