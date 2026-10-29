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

    backend: str = "llama-server"
    time_to_first_token_ms: float | None = None
    queue_time_ms: float | None = None
    generation_time_ms: float | None = None
    mean_itl_ms: float | None = None
    overall_output_tokens_per_second: float | None = None
    reasoning_tokens: int | None = None
    mean_acceptance_length: float | None = None
    reported_draft_acceptance_rate: float | None = None

    @property
    def uncached_prompt_tokens(self) -> int | None:
        if self.backend == "llama-server":
            return self.prompt_tokens
        if self.cached_tokens is None or not 0 <= self.cached_tokens <= self.prompt_tokens:
            return None
        return self.prompt_tokens - self.cached_tokens

    @property
    def estimated_input_tokens_per_second(self) -> float | None:
        uncached = self.uncached_prompt_tokens
        if (self.backend not in ("vllm", "sglang") or uncached is None or uncached <= 0
                or self.time_to_first_token_ms is None or self.time_to_first_token_ms <= 0):
            return None
        # TTFT includes first-token work and other overhead, not pure prefill.
        return uncached * 1000 / self.time_to_first_token_ms

    @property
    def estimated_decode_tokens_per_second(self) -> float | None:
        if self.backend == "sglang" and self.predicted_tokens_per_second > 0:
            return self.predicted_tokens_per_second
        if (self.backend not in ("vllm", "sglang") or self.predicted_tokens <= 1
                or self.generation_time_ms is None or self.generation_time_ms <= 0):
            return None
        # Decode duration starts at the first token: N tokens span N-1 intervals.
        return (self.predicted_tokens - 1) * 1000 / self.generation_time_ms

    @property
    def input_tokens(self) -> int:
        """vLLM prompt usage includes cached input; llama-server prompt_n does not."""
        return self.prompt_tokens + ((self.cached_tokens or 0) if self.backend == "llama-server" else 0)

    @property
    def context_tokens(self) -> int:
        return self.input_tokens + self.predicted_tokens

    @property
    def total_tokens(self) -> int:
        """Total tokens = prompt + predicted."""
        return self.prompt_tokens + self.predicted_tokens

    @property
    def draft_acceptance_rate(self) -> float | None:
        """Calculate draft token acceptance rate.
        
        Returns:
            Acceptance rate as a percentage (0-100), or None if draft data
            is unavailable or draft_tokens is zero.
        """
        if self.reported_draft_acceptance_rate is not None:
            return self.reported_draft_acceptance_rate * 100
        if self.draft_tokens is None or self.draft_tokens == 0:
            return None
        if self.backend != "llama-server" and self.draft_tokens_accepted is None:
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

    Use total input (cached plus new), so OpenAI prompt usage is not double counted.
    Every token the model saw or produced in the prior generation should be
    available in the prompt cache for the next one:

        expected_next_cache = prev.cache_n + prev.prompt_n + prev.predicted_n

    Returns None if the prior generation has no cache data to carry forward.
    """
    if prev.cached_tokens is None:
        return None
    return prev.input_tokens + prev.predicted_tokens


def detect_cache_misses(
    timings_list: list[ModelTimings], tolerance: int = 1
) -> list[CacheState | None]:
    """Compare each generation's cache against the prior generation's state.

    Args:
        timings_list: Assistant generations in trace order.
        tolerance: Absolute delta at or below this value is treated as a
            cache hit. The default of 1 absorbs benign off-by-one token
            counting artifacts while still flagging real cache drops.

    Returns:
        A list with one entry per generation. The first entry is always None
        (no prior state to compare against). Entries may also be None when
        cache data is unavailable on either side.
    """
    states: list[CacheState | None] = []
    prev: ModelTimings | None = None
    for timings in timings_list:
        if prev is None or timings.backend != prev.backend:
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
                        is_cache_miss=abs(actual - expected) > tolerance,
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
    sglang_choices = timings.get("choices") if isinstance(timings, dict) else None
    patched_sglang = isinstance(sglang_choices, list)
    # Usage can aggregate choices. Never attach one choice's timings to that total.
    single_choice = (sglang_choices[0] if patched_sglang and len(sglang_choices) == 1
                     and isinstance(sglang_choices[0], dict) else {})
    if patched_sglang or not timings or not isinstance(timings, dict):
        usage = last_sse.get("usage")
        native_meta = single_choice or last_sse.get("meta_info") or {}
        if not native_meta and isinstance(last_sse.get("choices"), list):
            choices = last_sse["choices"]
            if len(choices) == 1 and isinstance(choices[0], dict):
                native_meta = choices[0].get("meta_info") or {}
        if not isinstance(usage, dict) and isinstance(native_meta, dict) and "prompt_tokens" in native_meta:
            usage = {"prompt_tokens": native_meta.get("prompt_tokens"),
                     "completion_tokens": native_meta.get("completion_tokens"),
                     "prompt_tokens_details": {"cached_tokens": native_meta.get("cached_tokens")},
                     "reasoning_tokens": native_meta.get("reasoning_tokens")}
        if not isinstance(usage, dict) or not usage:
            return None
        metrics = last_sse.get("metrics") or {}
        prompt_details = usage.get("prompt_tokens_details") or {}
        completion_details = usage.get("completion_tokens_details") or {}
        speculative = metrics.get("speculative_decoding") or {}
        sglext = last_sse.get("sglext") or {}
        is_sglang = (patched_sglang or last_sse.get("response_backend") == "sglang" or bool(sglext)
                     or bool(native_meta) or "reasoning_tokens" in usage)
        if is_sglang:
            spec = native_meta or sglext.get("spec_tokens_details") or {}
            def milliseconds(key):
                value = native_meta.get(key)
                return value * 1000 if isinstance(value, (int, float)) and value >= 0 else None
            ttft = milliseconds("first_token_latency")
            elapsed = milliseconds("e2e_latency")
            decode = elapsed - ttft if elapsed is not None and ttft is not None and elapsed >= ttft else None
            # Multiple choices have distinct speculative stats; don't pick one.
            if not isinstance(spec, dict):
                spec = {}
            return ModelTimings(
                backend="sglang", prompt_tokens=usage.get("prompt_tokens") or 0,
                predicted_tokens=usage.get("completion_tokens") or 0,
                cached_tokens=prompt_details.get("cached_tokens", native_meta.get("cached_tokens")),
                reasoning_tokens=usage.get("reasoning_tokens"),
                time_to_first_token_ms=ttft, queue_time_ms=milliseconds("queue_time"),
                generation_time_ms=decode,
                predicted_tokens_per_second=native_meta.get("decode_throughput") or 0,
                mean_itl_ms=(1000 / native_meta["decode_throughput"]
                             if (native_meta.get("decode_throughput") or 0) > 0 else None),
                overall_output_tokens_per_second=(usage.get("completion_tokens", 0) * 1000 / elapsed
                                                  if elapsed and elapsed > 0 else None),
                draft_tokens=spec.get("spec_num_proposed_drafts"),
                draft_tokens_accepted=spec.get("spec_num_correct_drafts"),
                reported_draft_acceptance_rate=spec.get("spec_accept_rate"),
                mean_acceptance_length=spec.get("spec_accept_length"),
            )
        return ModelTimings(
            backend="vllm",
            prompt_tokens=usage.get("prompt_tokens") or 0,
            predicted_tokens=usage.get("completion_tokens") or 0,
            cached_tokens=prompt_details.get("cached_tokens"),
            reasoning_tokens=completion_details.get("reasoning_tokens"),
            time_to_first_token_ms=metrics.get("time_to_first_token_ms"),
            queue_time_ms=metrics.get("queue_time_ms"),
            generation_time_ms=metrics.get("generation_time_ms"),
            mean_itl_ms=metrics.get("mean_itl_ms"),
            overall_output_tokens_per_second=metrics.get("tokens_per_second"),
            draft_tokens=speculative.get("num_draft_tokens"),
            draft_tokens_accepted=speculative.get("num_accepted_draft_tokens"),
            reported_draft_acceptance_rate=speculative.get("draft_acceptance_rate"),
            mean_acceptance_length=speculative.get("mean_acceptance_length"),
        )

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
    token_parts = [f"{_humanize_int(timings.context_tokens)} tokens"]
    
    if timings.cached_tokens is not None and timings.cached_tokens > 0:
        token_parts.insert(0, f"{_humanize_int(timings.cached_tokens)} cached")
    
    parts.append(" ".join(token_parts))
    
    if timings.backend in ("vllm", "sglang"):
        if timings.time_to_first_token_ms is not None:
            parts.append(f"{_humanize_float(timings.time_to_first_token_ms)}ms TTFT")
        if timings.generation_time_ms is not None:
            parts.append(f"{_humanize_float(timings.generation_time_ms)}ms decode")

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

    if timings.backend in ("vllm", "sglang"):
        uncached = timings.uncached_prompt_tokens
        input_label = "in (includes cached)" if uncached is None else "in"
        input_count = timings.prompt_tokens if uncached is None else uncached
        input_rate = timings.estimated_input_tokens_per_second
        input_speed = f" @ ≈{_humanize_float(input_rate)} tok/s" if input_rate is not None else ""
        lines.append(f"[{color}]{input_label}: {_humanize_int(input_count)}{input_speed}[/]")
        for label, value in (("TTFT", timings.time_to_first_token_ms), ("queue", timings.queue_time_ms)):
            if value is not None and (label != "queue" or value >= 0.05):
                lines.append(f"[{color}]{label}: {_humanize_float(value)} ms[/]")
        output_rate = timings.estimated_decode_tokens_per_second
        output_speed = f" @ ≈{_humanize_float(output_rate)} tok/s" if output_rate is not None else ""
        lines.append(f"[{color}]out: {_humanize_int(timings.predicted_tokens)}{output_speed}[/]")
        if timings.reasoning_tokens is not None and timings.reasoning_tokens > 0:
            lines.append(f"[{color}]  reasoning: {_humanize_int(timings.reasoning_tokens)} tokens[/]")

    # Inbound speed
    if timings.prompt_tokens_per_second > 0:
        lines.append(f"[{color}]in: {_humanize_int(timings.prompt_tokens)} @ {_humanize_float(timings.prompt_tokens_per_second)} tok/s[/]")

    # Outbound speed
    if timings.backend == "llama-server" and timings.predicted_tokens_per_second > 0:
        lines.append(f"[{color}]out: {_humanize_int(timings.predicted_tokens)} @ {_humanize_float(timings.predicted_tokens_per_second)} tok/s[/]")

    # Draft tokens (speculative decoding / MTP)
    if timings.draft_tokens is not None and timings.draft_tokens > 0:
        draft_accepted = timings.draft_tokens_accepted or 0
        acceptance_rate = timings.formatted_acceptance_rate
        if timings.backend != "llama-server" and timings.draft_tokens_accepted is None:
            suffix = f", {acceptance_rate} accepted" if acceptance_rate else ""
            lines.append(f"[{color}]  draft: {_humanize_int(timings.draft_tokens)} proposed{suffix}[/]")
        elif acceptance_rate:
            lines.append(f"[{color}]  draft: {acceptance_rate} accepted ({_humanize_int(draft_accepted)} / {_humanize_int(timings.draft_tokens)} tokens)[/]")
        else:
            lines.append(f"[{color}]  draft: {_humanize_int(draft_accepted)} accepted ({_humanize_int(draft_accepted)} / {_humanize_int(timings.draft_tokens)} tokens)[/]")

    if timings.backend in ("vllm", "sglang"):
        if timings.mean_acceptance_length is not None:
            lines.append(f"[{color}]    mean acceptance length: {_humanize_float(timings.mean_acceptance_length)} tokens[/]")
        for label, value, unit in (
            ("  decode", timings.generation_time_ms, "ms"),
            ("  mean ITL", timings.mean_itl_ms, "ms"),
        ):
            if value is not None:
                lines.append(f"[{color}]{label}: {_humanize_float(value)} {unit}[/]")

    duration = timings.prompt_ms + timings.predicted_ms
    if duration > 0:
        lines.append(f"[dim {color}]⏱️ {_humanize_float(duration, 0)}ms[/]")

    return "\n".join(lines)
