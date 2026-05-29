"""Parse and format model inference timings from trace data."""

from dataclasses import dataclass
from typing import Any


@dataclass
class ModelTimings:
    """Parsed timing information from a model inference response."""

    prompt_tokens: int = 0
    predicted_tokens: int = 0
    cached_tokens: int | None = None
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
        prompt_ms=timings.get("prompt_ms", 0.0),
        predicted_ms=timings.get("predicted_ms", 0.0),
        prompt_tokens_per_second=timings.get("prompt_per_second", 0.0),
        predicted_tokens_per_second=timings.get("predicted_per_second", 0.0),
    )


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
    token_parts = [f"{timings.total_tokens} tokens"]
    
    if timings.cached_tokens is not None and timings.cached_tokens > 0:
        token_parts.insert(0, f"{timings.cached_tokens} cached")
    
    parts.append(" ".join(token_parts))
    
    # Add timing info
    if timings.prompt_ms > 0:
        parts.append(f"{timings.prompt_ms:.0f}ms prompt")
    
    if timings.predicted_ms > 0:
        parts.append(f"{timings.predicted_ms:.0f}ms predicted")
    
    return " | ".join(parts)


def format_stats_line(timings: ModelTimings | None) -> str:
    """Format a compact stats line for display (similar to AskRewrite format).
    
    Args:
        timings: The parsed ModelTimings object.
        
    Returns:
        Compact stats string, or empty string if no timings.
    """
    if not timings:
        return ""

    # Token breakdown: cached, prompt, predicted
    stats_parts = [f"[cyan]{timings.total_tokens} tokens[/]"]
    
    if timings.cached_tokens is not None and timings.cached_tokens > 0:
        stats_parts.append(f"[dim]({timings.cached_tokens} cached)[/]")
    
    stats_parts.append(f"[dim]in: {timings.prompt_tokens}[/]")
    stats_parts.append(f"[dim]out: {timings.predicted_tokens}[/]")
    
    # Add speed info
    if timings.predicted_tokens_per_second > 0:
        stats_parts.append(f"[dim]{timings.predicted_tokens_per_second:.1f} tok/s[/]")
    
    return " ".join(stats_parts)
