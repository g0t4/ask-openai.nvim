"""Parse and format model inference timings from trace data."""

from dataclasses import dataclass
from typing import Any


@dataclass
class ModelTimings:
    """Parsed timing information from a model inference response."""

    prompt_tokens: int = 0
    predicted_tokens: int = 0
    cached_tokens: int | None = None
    draft_tokens: int | None = None
    draft_tokens_accepted: int | None = None
    prompt_ms: float = 0.0
    predicted_ms: float = 0.0
    prompt_tokens_per_second: float = 0.0
    predicted_tokens_per_second: float = 0.0

    @property
    def total_tokens(self) -> int:
        """Total tokens = prompt + predicted."""
        return self.prompt_tokens + self.predicted_tokens

    @property
    def cache_hit_ratio(self) -> float | None:
        """Ratio of cached tokens to total input tokens (if cache available)."""
        if self.cached_tokens is None or self.total_tokens == 0:
            return None
        return self.cached_tokens / (self.prompt_tokens + self.cached_tokens)

    @property
    def formatted_cache_ratio(self) -> str | None:
        """Human-readable cache hit ratio, e.g. '34.2%'.
        
        Returns None if cache data is unavailable or ratio cannot be computed.
        """
        ratio = self.cache_hit_ratio
        if ratio is None:
            return None
        return f"{ratio * 100:.1f}%"

    @property
    def draft_acceptance_rate(self) -> float | None:
        """Calculate draft token acceptance rate.
        
        Returns:
            Acceptance rate as a percentage (0-100), or None if draft data
            is unavailable or draft_tokens is zero.
        """
        if self.draft_tokens is None or self.draft_tokens == 0:
            return None
        accepted = self.draft_tokens_accepted or 0
        return (accepted / self.draft_tokens) * 100

    @property
    def formatted_acceptance_rate(self) -> str | None:
        """Human-readable draft acceptance rate, e.g. '80.8%'.
        
        Returns None if draft data is unavailable or rate cannot be computed.
        """
        rate = self.draft_acceptance_rate
        if rate is None:
            return None
        return f"{rate:.1f}%"


@dataclass
class CacheState:
    """Cache continuity between two consecutive assistant generations.

    The cache is expected to carry forward every token from the prior
    generation: the previously cached prefix plus the newly processed prompt
    plus the newly generated output. If the next generation's ``cache_n``
    differs, some cached context was dropped (or a cache miss occurred).
    """

    expected_cache_tokens: int | None
    actual_cache_tokens: int | None
    is_cache_miss: bool
    missing_tokens: int | None

    @property
    def formatted_missing_tokens(self) -> str | None:
        """Human-readable cache delta, e.g. '-680' or '+1'."""
        if self.missing_tokens is None:
            return None
        if self.missing_tokens >= 0:
            return f"+{_humanize_int(self.missing_tokens)}"
        return _humanize_int(self.missing_tokens)


def expected_next_cache(prev: ModelTimings) -> int | None:
    """Expected ``cache_n`` for the request following ``prev``'s generation.

    Every token the model saw or produced in the prior generation should be
    available in the prompt cache for the next one:

        expected_next_cache = prev.cache_n + prev.prompt_n + prev.predicted_n

    Returns None if the prior generation has no cache data to carry forward.
    """
    if prev.cached_tokens is None:
        return None
    return prev.cached_tokens + prev.prompt_tokens + prev.predicted_tokens


def detect_cache_misses(timings_list: list[ModelTimings]) -> list[CacheState | None]:
    """Compare each generation's cache against the prior generation's state.

    Args:
        timings_list: Assistant generations in trace order.

    Returns:
        A list with one entry per generation. The first entry is always None
        (no prior state to compare against). Entries may also be None when
        cache data is unavailable on either side.
    """
    states: list[CacheState | None] = []
    prev: ModelTimings | None = None
    for timings in timings_list:
        if prev is None:
            states.append(None)
        else:
            expected = expected_next_cache(prev)
            actual = timings.cached_tokens
            if expected is None or actual is None:
                states.append(None)
            else:
                states.append(
                    CacheState(
                        expected_cache_tokens=expected,
                        actual_cache_tokens=actual,
                        is_cache_miss=expected != actual,
                        missing_tokens=actual - expected,
                    )
                )
        prev = timings
    return states


def parse_timings(last_sse: dict[str, Any] | None) -> ModelTimings | None:
    """Extract timing information from the last SSE response.
    
    Args:
        last_sse: The last server-sent event from the trace data.
        
    Returns:
        ModelTimings if timings data is available, None otherwise.
    """
    if not last_sse:
        return None

    timings = last_sse.get("timings")
    if not timings or not isinstance(timings, dict):
        return None

    return ModelTimings(
        prompt_tokens=timings.get("prompt_n", 0),
        predicted_tokens=timings.get("predicted_n", 0),
        cached_tokens=timings.get("cache_n"),
        draft_tokens=timings.get("draft_n"),
        draft_tokens_accepted=timings.get("draft_n_accepted"),
        prompt_ms=timings.get("prompt_ms", 0.0),
        predicted_ms=timings.get("predicted_ms", 0.0),
        prompt_tokens_per_second=timings.get("prompt_per_second", 0.0),
        predicted_tokens_per_second=timings.get("predicted_per_second", 0.0),
    )


def _humanize_int(value: int) -> str:
    """Format an integer with comma separators for readability.
    
    Examples:
        1000 => "1,000"
        1000000 => "1,000,000"
    """
    return f"{value:,}"


def _humanize_float(value: float, decimals: int = 1) -> str:
    """Format a float with comma separators and specified decimal places.
    
    Examples:
        1234.5 => "1,234.5"
        1234.567 => "1,234.6"
    """
    return f"{value:,.{decimals}f}"


def format_timings_display(timings: ModelTimings | None) -> str:
    """Format timings for display under the model name.
    
    Args:
        timings: The parsed ModelTimings object.
        
    Returns:
        Formatted string for display, or empty string if no timings.
    """
    if not timings:
        return ""

    parts: list[str] = []
    
    # Token counts: total + cached + prompt vs predicted breakdown
    token_parts = [f"{_humanize_int(timings.total_tokens)} tokens"]
    
    if timings.cached_tokens is not None and timings.cached_tokens > 0:
        token_parts.insert(0, f"{_humanize_int(timings.cached_tokens)} cached")
    
    parts.append(" ".join(token_parts))
    
    # Add timing info
    if timings.prompt_ms > 0:
        parts.append(f"{_humanize_float(timings.prompt_ms, 0)}ms prompt")
    
    if timings.predicted_ms > 0:
        parts.append(f"{_humanize_float(timings.predicted_ms, 0)}ms predicted")
    
    return " | ".join(parts)


def format_stats_line(timings: ModelTimings | None, color: str = "dim") -> str:
    """Format multi-line stats for display (similar to AskRewrite format).

    Args:
        timings: The parsed ModelTimings object.
        color: Rich color name used for the lines (e.g. a role color).

    Returns:
        Multi-line stats string, or empty string if no timings.
    """
    if not timings:
        return ""

    lines: list[str] = []

    # Cache tokens (if present and > 0)
    if timings.cached_tokens is not None and timings.cached_tokens > 0:
        lines.append(f"[{color}]cached: {_humanize_int(timings.cached_tokens)} tokens[/]")

    # Inbound speed
    if timings.prompt_tokens_per_second > 0:
        lines.append(f"[{color}]in: {_humanize_int(timings.prompt_tokens)} tokens @ {_humanize_float(timings.prompt_tokens_per_second)} tok/s[/]")

    # Outbound speed
    if timings.predicted_tokens_per_second > 0:
        lines.append(f"[{color}]out: {_humanize_int(timings.predicted_tokens)} tokens @ {_humanize_float(timings.predicted_tokens_per_second)} tok/s[/]")

    # Draft tokens (speculative decoding / MTP)
    if timings.draft_tokens is not None and timings.draft_tokens > 0:
        draft_accepted = timings.draft_tokens_accepted or 0
        acceptance_rate = timings.formatted_acceptance_rate
        if acceptance_rate:
            lines.append(f"[{color}]  draft: {acceptance_rate} accepted ({_humanize_int(draft_accepted)} / {_humanize_int(timings.draft_tokens)} tokens)[/]")
        else:
            lines.append(f"[{color}]  draft: {_humanize_int(draft_accepted)} accepted ({_humanize_int(draft_accepted)} / {_humanize_int(timings.draft_tokens)} tokens)[/]")

    duration = timings.prompt_ms + timings.predicted_ms
    if duration > 0:
        lines.append(f"[dim {color}]⏱️ {_humanize_float(duration, 0)}ms[/]")

    return "\n".join(lines)
