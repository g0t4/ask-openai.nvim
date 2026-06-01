"""Parse and format tool call timing information."""

from dataclasses import dataclass
from typing import Any


@dataclass
class ToolCallTimings:
    """Parsed timing information for a tool call."""

    duration_ms: int = 0
    start_time_ms: int = 0

    @property
    def formatted_duration(self) -> str:
        """Human-readable duration, e.g. '1.2s' or '3m45s'."""
        return format_duration_ms(self.duration_ms)

    @property
    def formatted_start_time(self) -> str:
        """Human-readable start timestamp as local time."""
        import datetime
        try:
            dt = datetime.datetime.fromtimestamp(
                self.start_time_ms / 1000, tz=datetime.timezone.utc
            )
            return dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except (OSError, ValueError, OverflowError):
            return str(self.start_time_ms)


def format_duration_ms(duration_ms: int) -> str:
    """Format a duration in milliseconds into a human-readable string.

    Args:
        duration_ms: Duration in milliseconds.

    Returns:
        Formatted string:
            - < 1000ms: "{N}ms"
            - < 60000ms (60s): "{X.X}s" (1 decimal, trims trailing zero if whole number)
            - >= 60000ms: "{M}m{S}s" (whole minutes + whole seconds)

    Examples:
        100 => "100ms"
        999 => "999ms"
        1000 => "1s"
        1100 => "1.1s"
        1500 => "1.5s"
        2000 => "2s"
        59999 => "59.9s"
        60000 => "1m0s"
        100000 => "1m40s"
        3661000 => "61m1s"
    """
    if duration_ms < 1000:
        return f"{duration_ms}ms"

    seconds = duration_ms / 1000.0
    if seconds < 60:
        # Round to 1 decimal place
        rounded_seconds = round(seconds, 1)
        # Check if it's a whole number after rounding
        if rounded_seconds == int(rounded_seconds):
            return f"{int(rounded_seconds)}s"
        return f"{rounded_seconds}s"

    minutes = int(seconds // 60)
    whole_seconds = int(seconds % 60)
    return f"{minutes}m{whole_seconds}s"


def parse_tool_call_timings(msg: dict[str, Any]) -> ToolCallTimings | None:
    """Extract tool call timing info from a tool result message.

    Args:
        msg: A tool result message dict (TxChatMessage with role="tool").

    Returns:
        ToolCallTimings if duration_ms is present, None otherwise.
    """
    duration_ms = msg.get("duration_ms")
    start_time_ms = msg.get("start_time_ms", 0)

    if duration_ms is None:
        return None

    return ToolCallTimings(
        duration_ms=duration_ms,
        start_time_ms=start_time_ms,
    )
