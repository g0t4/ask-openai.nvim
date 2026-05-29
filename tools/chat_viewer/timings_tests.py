"""Tests for the timings module."""

import sys
import os

# Ensure we can import from the chat_viewer package
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from tools.chat_viewer.timings import (
    ModelTimings,
    parse_timings,
    format_timings_display,
    format_stats_line,
    _humanize_int,
    _humanize_float,
)


def test_humanize_int_small() -> None:
    """Test humanizing small integers."""
    assert _humanize_int(100) == "100"
    assert _humanize_int(1000) == "1,000"
    assert _humanize_int(10000) == "10,000"
    assert _humanize_int(1000000) == "1,000,000"
    assert _humanize_int(10000000) == "10,000,000"
    assert _humanize_int(0) == "0"


def test_humanize_float_small() -> None:
    """Test humanizing small floats."""
    assert _humanize_float(1234.5) == "1,234.5"
    # Default decimals is 1, so 1234.567 rounds to 1234.6
    assert _humanize_float(1234.567) == "1,234.6"
    assert _humanize_float(100.0) == "100.0"
    assert _humanize_float(0.0) == "0.0"


def test_humanize_float_custom_decimals() -> None:
    """Test humanizing floats with custom decimal places."""
    assert _humanize_float(1234.567, 2) == "1,234.57"
    assert _humanize_float(1234.567, 0) == "1,235"


def test_parse_timings_basic() -> None:
    """Test parsing basic timing information."""
    last_sse = {
        "timings": {
            "prompt_n": 129,
            "predicted_n": 296,
            "cache_n": 349,
            "prompt_ms": 64.15,
            "predicted_ms": 1137.496,
            "prompt_per_second": 2010.91,
            "predicted_per_second": 260.22,
        }
    }
    
    timings = parse_timings(last_sse)
    
    assert timings is not None
    assert timings.prompt_tokens == 129
    assert timings.predicted_tokens == 296
    assert timings.cached_tokens == 349
    assert timings.prompt_ms == 64.15
    assert timings.predicted_ms == 1137.496
    assert timings.prompt_tokens_per_second == 2010.91
    assert timings.predicted_tokens_per_second == 260.22


def test_parse_timings_with_draft() -> None:
    """Test parsing speculative decoding (draft) timing information."""
    last_sse = {
        "timings": {
            "prompt_n": 129,
            "predicted_n": 296,
            "cache_n": 349,
            "draft_n": 125,
            "draft_n_accepted": 101,
            "prompt_per_second": 2010.91,
            "predicted_per_second": 260.22,
        }
    }
    
    timings = parse_timings(last_sse)
    
    assert timings is not None
    assert timings.draft_tokens == 125
    assert timings.draft_tokens_accepted == 101


def test_parse_timings_no_timings() -> None:
    """Test that None is returned when timings data is missing."""
    assert parse_timings(None) is None
    assert parse_timings({}) is None
    assert parse_timings({"model": "test"}) is None
    assert parse_timings({"timings": None}) is None
    assert parse_timings({"timings": {}}) is None


def test_parse_timings_empty_timings() -> None:
    """Test parsing when timings dict is empty returns None."""
    last_sse = {"timings": {}}
    timings = parse_timings(last_sse)
    
    # Empty timings dict should return None
    assert timings is None


def test_parse_timings_missing_cache() -> None:
    """Test parsing when cache_n is missing."""
    last_sse = {
        "timings": {
            "prompt_n": 100,
            "predicted_n": 50,
        }
    }
    
    timings = parse_timings(last_sse)
    
    assert timings is not None
    assert timings.cached_tokens is None


def test_total_tokens() -> None:
    """Test total token calculation."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
    )
    
    assert timings.total_tokens == 150


def test_total_tokens_with_no_input() -> None:
    """Test total token calculation with zero values."""
    timings = ModelTimings()
    
    assert timings.total_tokens == 0


def test_cache_hit_ratio() -> None:
    """Test cache hit ratio calculation."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
        cached_tokens=349,
    )
    
    assert timings.cache_hit_ratio is not None
    # cache_hit_ratio = cached / (prompt + cached) = 349 / (100 + 349)
    expected_ratio = 349 / (100 + 349)
    assert abs(timings.cache_hit_ratio - expected_ratio) < 0.0001


def test_cache_hit_ratio_with_no_cache() -> None:
    """Test cache hit ratio when no cache data."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
    )
    
    assert timings.cache_hit_ratio is None


def test_cache_hit_ratio_with_zero_cache() -> None:
    """Test cache hit ratio when cache is zero."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
        cached_tokens=0,
    )
    
    assert timings.cache_hit_ratio is not None
    assert timings.cache_hit_ratio == 0.0


def test_formatted_cache_ratio() -> None:
    """Test formatted cache ratio string."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
        cached_tokens=349,
    )
    
    formatted = timings.formatted_cache_ratio
    assert formatted is not None
    # Should contain percentage sign and be approximately 77.7%
    assert "%" in formatted
    assert "77.7" in formatted


def test_formatted_cache_ratio_no_cache() -> None:
    """Test formatted cache ratio when no cache data."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
    )
    
    assert timings.formatted_cache_ratio is None


def test_format_timings_display_empty() -> None:
    """Test formatting with no timings."""
    assert format_timings_display(None) == ""


def test_format_timings_display_basic() -> None:
    """Test basic formatting."""
    timings = ModelTimings(
        prompt_tokens=129,
        predicted_tokens=296,
        cached_tokens=349,
        prompt_ms=64.15,
        predicted_ms=1137.496,
    )
    
    display = format_timings_display(timings)
    assert "425 tokens" in display  # 129 + 296 = 425
    assert "349 cached" in display
    assert "64ms prompt" in display
    assert "1,137ms predicted" in display


def test_format_timings_display_large_numbers() -> None:
    """Test formatting with large numbers that get comma-separated."""
    timings = ModelTimings(
        prompt_tokens=10000,
        predicted_tokens=50000,
        cached_tokens=25000,
        prompt_ms=1234.5,
        predicted_ms=5678.9,
    )
    
    display = format_timings_display(timings)
    assert "60,000 tokens" in display
    assert "25,000 cached" in display
    # format_timings_display uses 0 decimals for ms
    assert "1,234ms prompt" in display
    assert "5,679ms predicted" in display


def test_format_stats_line_empty() -> None:
    """Test stats line formatting with no timings."""
    assert format_stats_line(None) == ""


def test_format_stats_line_basic() -> None:
    """Test basic stats line formatting."""
    timings = ModelTimings(
        prompt_tokens=129,
        predicted_tokens=296,
        cached_tokens=349,
        prompt_tokens_per_second=2010.91,
        predicted_tokens_per_second=260.22,
    )
    
    stats = format_stats_line(timings)
    
    # Should be multi-line
    lines = stats.split("\n")
    assert len(lines) >= 3
    
    # Check each line
    assert "cached: 349 tokens" in lines[0]
    assert "in: 129 tokens @ 2,010.9 tok/sec" in lines[1]
    assert "out: 296 tokens @ 260.2 tok/sec" in lines[2]


def test_format_stats_line_large_numbers() -> None:
    """Test stats line formatting with large numbers."""
    timings = ModelTimings(
        prompt_tokens=10000,
        predicted_tokens=50000,
        cached_tokens=25000,
        prompt_tokens_per_second=100000.5,
        predicted_tokens_per_second=5000.1,
    )
    
    stats = format_stats_line(timings)
    lines = stats.split("\n")
    
    assert "cached: 25,000 tokens" in lines[0]
    assert "in: 10,000 tokens @ 100,000.5 tok/sec" in lines[1]
    assert "out: 50,000 tokens @ 5,000.1 tok/sec" in lines[2]


def test_format_stats_line_with_draft() -> None:
    """Test stats line formatting with speculative decoding (draft) info."""
    timings = ModelTimings(
        prompt_tokens=129,
        predicted_tokens=296,
        cached_tokens=349,
        draft_tokens=125,
        draft_tokens_accepted=101,
        prompt_tokens_per_second=2010.91,
        predicted_tokens_per_second=260.22,
    )
    
    stats = format_stats_line(timings)
    lines = stats.split("\n")
    
    # Should have 4 lines: cached, in, out, draft
    assert len(lines) == 4
    assert "cached: 349 tokens" in lines[0]
    assert "in: 129 tokens @ 2,010.9 tok/sec" in lines[1]
    assert "out: 296 tokens @ 260.2 tok/sec" in lines[2]
    assert "  draft:" in lines[3]
    assert "80.8% accepted" in lines[3]  # 101/125 = 80.8%
    assert "101 / 125 tokens" in lines[3]


def test_format_stats_line_no_cache() -> None:
    """Test stats line formatting without cache data."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
        prompt_tokens_per_second=100.0,
        predicted_tokens_per_second=50.0,
    )
    
    stats = format_stats_line(timings)
    lines = stats.split("\n")
    
    # Should only have 2 lines: in, out (no cached line)
    assert len(lines) == 2
    assert "in: 100 tokens @ 100.0 tok/sec" in lines[0]
    assert "out: 50 tokens @ 50.0 tok/sec" in lines[1]


def test_format_stats_line_no_speed() -> None:
    """Test stats line formatting without speed data."""
    timings = ModelTimings(
        prompt_tokens=100,
        predicted_tokens=50,
        cached_tokens=300,
    )
    
    stats = format_stats_line(timings)
    lines = stats.split("\n")
    
    # Should only have cached line (no speed data)
    assert len(lines) == 1
    assert "cached: 300 tokens" in lines[0]


def test_format_stats_line_zero_draft_accepted() -> None:
    """Test stats line formatting when draft_tokens but zero accepted."""
    timings = ModelTimings(
        prompt_tokens=129,
        predicted_tokens=296,
        prompt_tokens_per_second=2010.91,
        predicted_tokens_per_second=260.22,
        draft_tokens=125,
        draft_tokens_accepted=0,
    )
    
    stats = format_stats_line(timings)
    lines = stats.split("\n")
    
    # Should have 3 lines: in, out, draft (no cached)
    assert len(lines) == 3
    assert "  draft:" in lines[2]
    assert "0.0% accepted" in lines[2]  # 0/125 = 0.0%
    assert "0 / 125 tokens" in lines[2]


def test_draft_acceptance_rate() -> None:
    """Test draft acceptance rate calculation."""
    timings = ModelTimings(
        draft_tokens=125,
        draft_tokens_accepted=101,
    )
    
    assert timings.draft_acceptance_rate is not None
    expected_rate = (101 / 125) * 100
    assert abs(timings.draft_acceptance_rate - expected_rate) < 0.01


def test_draft_acceptance_rate_no_draft() -> None:
    """Test draft acceptance rate when no draft data."""
    timings = ModelTimings()
    assert timings.draft_acceptance_rate is None


def test_draft_acceptance_rate_zero_draft() -> None:
    """Test draft acceptance rate when draft_tokens is zero."""
    timings = ModelTimings(
        draft_tokens=0,
        draft_tokens_accepted=0,
    )
    assert timings.draft_acceptance_rate is None


def test_formatted_acceptance_rate() -> None:
    """Test formatted acceptance rate string."""
    timings = ModelTimings(
        draft_tokens=125,
        draft_tokens_accepted=101,
    )
    
    formatted = timings.formatted_acceptance_rate
    assert formatted is not None
    assert formatted == "80.8%"


def test_formatted_acceptance_rate_no_draft() -> None:
    """Test formatted acceptance rate when no draft data."""
    timings = ModelTimings()
    assert timings.formatted_acceptance_rate is None


def test_formatted_acceptance_rate_zero_draft() -> None:
    """Test formatted acceptance rate when draft_tokens is zero."""
    timings = ModelTimings(
        draft_tokens=0,
        draft_tokens_accepted=0,
    )
    assert timings.formatted_acceptance_rate is None


def test_formatted_acceptance_rate_perfect_rate() -> None:
    """Test formatted acceptance rate with 100%."""
    timings = ModelTimings(
        draft_tokens=100,
        draft_tokens_accepted=100,
    )
    
    formatted = timings.formatted_acceptance_rate
    assert formatted is not None
    assert formatted == "100.0%"
