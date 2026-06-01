"""Tests for the timing_utils module."""

import sys
import os

# Ensure we can import from the chat_viewer package
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from tools.chat_viewer.timing_utils import (
    format_duration_ms,
    parse_tool_call_timings,
    ToolCallTimings,
)


# ---- format_duration_ms tests ----


def test_format_duration_ms_under_one_second() -> None:
    """Test durations under 1000ms show as milliseconds."""
    assert format_duration_ms(0) == "0ms"
    assert format_duration_ms(1) == "1ms"
    assert format_duration_ms(99) == "99ms"
    assert format_duration_ms(999) == "999ms"


def test_format_duration_ms_exact_one_second() -> None:
    """Test exactly 1000ms shows as '1s' (no .0)."""
    assert format_duration_ms(1000) == "1s"


def test_format_duration_ms_one_point_one_seconds() -> None:
    """Test 1100ms shows as '1.1s'."""
    assert format_duration_ms(1100) == "1.1s"


def test_format_duration_ms_two_point_five_seconds() -> None:
    """Test 2500ms shows as '2.5s'."""
    assert format_duration_ms(2500) == "2.5s"


def test_format_duration_ms_nine_point_nine_seconds() -> None:
    """Test 9900ms shows as '9.9s'."""
    assert format_duration_ms(9900) == "9.9s"


def test_format_duration_ms_round_seconds() -> None:
    """Test whole seconds trim trailing .0."""
    assert format_duration_ms(2000) == "2s"
    assert format_duration_ms(3000) == "3s"
    assert format_duration_ms(59000) == "59s"


def test_format_duration_ms_one_minute() -> None:
    """Test exactly 60 seconds shows as '1m0s'."""
    assert format_duration_ms(60000) == "1m0s"


def test_format_duration_ms_one_minute_forty_seconds() -> None:
    """Test 100000ms (1m40s) shows as '1m40s'."""
    assert format_duration_ms(100000) == "1m40s"


def test_format_duration_ms_two_minutes() -> None:
    """Test 120000ms shows as '2m0s'."""
    assert format_duration_ms(120000) == "2m0s"


def test_format_duration_ms_large_values() -> None:
    """Test large duration values."""
    assert format_duration_ms(3661000) == "61m1s"  # 61m1s
    assert format_duration_ms(37230000) == "620m30s"  # 620m30s


def test_format_duration_ms_fractional_rounding() -> None:
    """Test that fractions round correctly to 1 decimal."""
    assert format_duration_ms(1050) == "1.1s"  # 1.05 rounds to 1.1 (round half to even)
    assert format_duration_ms(1051) == "1.1s"
    assert format_duration_ms(1049) == "1s"  # 1.049 rounds to 1.0 → trimmed to "1s"


# ---- ToolCallTimings tests ----


def test_tool_call_timings_formatted_duration() -> None:
    """Test ToolCallTimings.formatted_duration property."""
    timings = ToolCallTimings(duration_ms=1500)
    assert timings.formatted_duration == "1.5s"

    timings2 = ToolCallTimings(duration_ms=950)
    assert timings2.formatted_duration == "950ms"

    timings3 = ToolCallTimings(duration_ms=120000)
    assert timings3.formatted_duration == "2m0s"


def test_tool_call_timings_formatted_start_time() -> None:
    """Test ToolCallTimings.formatted_start_time property."""
    import datetime
    now_ms = int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp() * 1000)
    timings = ToolCallTimings(start_time_ms=now_ms)
    formatted = timings.formatted_start_time
    # Should contain "UTC" and a valid timestamp
    assert "UTC" in formatted
    assert "-" in formatted  # date format YYYY-MM-DD


def test_tool_call_timings_formatted_start_time_invalid() -> None:
    """Test formatted_start_time handles extremely invalid timestamps gracefully."""
    # Use an absurdly large number that will cause OverflowError
    timings = ToolCallTimings(start_time_ms=99999999999999999999)
    # Should fall back to string representation
    assert timings.formatted_start_time == str(99999999999999999999)


# ---- parse_tool_call_timings tests ----


def test_parse_tool_call_timings_with_duration() -> None:
    """Test parsing timing from a tool result message."""
    msg = {
        "role": "tool",
        "duration_ms": 1500,
        "start_time_ms": 1234567890000,
        "content": '{"result": "ok"}',
    }
    timings = parse_tool_call_timings(msg)
    assert timings is not None
    assert timings.duration_ms == 1500
    assert timings.start_time_ms == 1234567890000
    assert timings.formatted_duration == "1.5s"


def test_parse_tool_call_timings_no_duration() -> None:
    """Test returning None when duration_ms is missing."""
    msg = {
        "role": "tool",
        "content": '{"result": "ok"}',
    }
    timings = parse_tool_call_timings(msg)
    assert timings is None


def test_parse_tool_call_timings_default_start_time() -> None:
    """Test default start_time_ms is 0 when not provided."""
    msg = {
        "role": "tool",
        "duration_ms": 500,
    }
    timings = parse_tool_call_timings(msg)
    assert timings is not None
    assert timings.duration_ms == 500
    assert timings.start_time_ms == 0
