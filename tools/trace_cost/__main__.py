#!/usr/bin/env python3
"""Estimate token cost of an agent trace with cache-aware pricing.

# manually compute:
# for trace in ~/repos/github/g0t4/datasets/ask_traces/agents/2026-06/**/*-trace.json; python3 tools/trace_cost/__main__.py $trace; end
# jq --raw-output '[.request_body.messages[] | select(.role=="assistant") | .timings] | reduce .[] as $t ({"cache_n":0,"prompt_n":0,"predicted_n":0}; .cache_n += ($t.cache_n //0) | .prompt_n += ($t.prompt_n //0) | .predicted_n += ($t.predicted_n //0))' 1780516440-trace.json

Reads a trace JSON file and computes the cost breakdown based on:
- Input tokens (first time seen) charged at full rate
- Input tokens (cached from previous generations) charged at cache-hit rate
- Output tokens (generated) charged at output rate

The cache accumulates across generations - tokens cached in early generations
remain available for later generations. Each token usage is charged based on
whether it was served from cache at the time of that generation.

Usage:
    python -m tools.trace_cost path/to/trace.json
    python -m tools.trace_cost --input-price 2.5 --cache-price 1.25 --output-price 10
"""

import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class PricingConfig:
    """Pricing configuration per 1M tokens."""

    input_price_per_million: float
    cache_price_per_million: float
    output_price_per_million: float

    @property
    def input_multiplier(self) -> float:
        """Price per single input token."""
        return self.input_price_per_million / 1_000_000

    @property
    def cache_multiplier(self) -> float:
        """Price per single cache-hit token."""
        return self.cache_price_per_million / 1_000_000

    @property
    def output_multiplier(self) -> float:
        """Price per single output token."""
        return self.output_price_per_million / 1_000_000


@dataclass
class TokenCostBreakdown:
    """Aggregate cost breakdown for a trace."""

    pricing: PricingConfig
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cached_tokens: int = 0
    model: str | None = None
    trace_id: str | None = None

    @property
    def input_cost(self) -> float:
        """Total input cost."""
        return self.total_input_tokens * self.pricing.input_multiplier

    @property
    def cached_cost(self) -> float:
        """Total cache cost."""
        return self.total_cached_tokens * self.pricing.cache_multiplier

    @property
    def output_cost(self) -> float:
        """Total output cost."""
        return self.total_output_tokens * self.pricing.output_multiplier

    @property
    def total_cost(self) -> float:
        """Total cost."""
        return self.input_cost + self.cached_cost + self.output_cost

    def format_token_count(self, count: int) -> str:
        """Format a token count with commas for readability.

        Args:
            count: Token count to format.

        Returns:
            Formatted string, e.g. "1,234".
        """
        return f"{count:,}"


DEFAULT_PRICING: dict[str, PricingConfig] = {
    "gpt-5.5": PricingConfig(
        input_price_per_million=5.0,
        cache_price_per_million=0.5,
        output_price_per_million=30.0,
    ),
    "gpt-5.5-pro": PricingConfig(
        input_price_per_million=30.0,
        cache_price_per_million=30.0,  # no cached token rate
        output_price_per_million=180.0,
    ),
    "gpt-5.4": PricingConfig(
        input_price_per_million=2.5,
        cache_price_per_million=0.25,
        output_price_per_million=15.0,
    ),
    "gpt-5.4-mini": PricingConfig(
        input_price_per_million=0.75,
        cache_price_per_million=0.075,
        output_price_per_million=4.50,
    ),
    "gpt-5.4-nano": PricingConfig(
        input_price_per_million=0.20,
        cache_price_per_million=0.02,
        output_price_per_million=1.25,
    ),
    "gpt-4o": PricingConfig(
        input_price_per_million=2.5,
        cache_price_per_million=1.25,
        output_price_per_million=10.0,
    ),
}

# Map partial model name substrings to pricing configs
MODEL_NAME_KEYS: list[str] = [key for key in DEFAULT_PRICING]


def _select_pricing_config(model_name: str | None) -> PricingConfig:
    """Select pricing config based on model name, falling back to defaults.

    Args:
        model_name: Full model name from the trace (e.g. "gpt-4o-2024-05-13").

    Returns:
        PricingConfig for the matching model, or first default if no match.
    """
    if not model_name:
        return DEFAULT_PRICING["gpt-4o"]

    model_lower = model_name.lower()

    # Try exact match first
    if model_name in DEFAULT_PRICING:
        return DEFAULT_PRICING[model_name]

    # Try substring match (e.g. "gpt-4o-mini-20240718" matches "gpt-4o-mini")
    for key in MODEL_NAME_KEYS:
        if key.lower() in model_lower:
            return DEFAULT_PRICING[key]

    default_model = "gpt-5.4"
    print(f"Warning: No pricing found for model '{model_name}', using {default_model} pricing as default", file=sys.stderr)
    return DEFAULT_PRICING[default_model]


def _calculate_cost(
    messages: list[dict[str, Any]],
    pricing: PricingConfig,
    model: str | None,
    trace_id: str | None,
) -> TokenCostBreakdown:
    """Calculate the cost breakdown for a trace.

    Args:
        messages: List of message dicts from request_body.messages.
        pricing: Pricing configuration for the model.
        model: Model name from the trace.
        trace_id: Trace identifier.

    Returns:
        TokenCostBreakdown with token counts (costs computed via properties).
    """
    total_input_tokens = 0
    total_cached_tokens = 0
    total_output_tokens = 0

    for message in messages:
        if message.get("role") != "assistant":
            continue

        timings = message.get("timings")
        if not timings:
            continue

        prompt_n = timings.get("prompt_n", 0)
        predicted_n = timings.get("predicted_n", 0)
        cache_n = timings.get("cache_n", 0)

        total_input_tokens += prompt_n
        total_cached_tokens += cache_n
        total_output_tokens += predicted_n

    return TokenCostBreakdown(
        pricing=pricing,
        total_input_tokens=total_input_tokens,
        total_cached_tokens=total_cached_tokens,
        total_output_tokens=total_output_tokens,
        model=model,
        trace_id=trace_id,
    )


def _format_breakdown(breakdown: TokenCostBreakdown) -> str:
    """Format cost breakdown as a readable string.

    Args:
        breakdown: The calculated cost breakdown.

    Returns:
        Formatted string for display.
    """
    lines: list[str] = []

    # --- Header ---
    model_display = breakdown.model or "unknown model"
    lines.append(f"Model: {model_display}")
    if breakdown.trace_id:
        lines.append(f"Trace: {breakdown.trace_id}")
    lines.append("")

    # --- Token counts ---
    lines.append("Token Counts:")
    lines.append(f"  Input (uncached)  : {breakdown.format_token_count(breakdown.total_input_tokens)}  (first-time, full price)")
    lines.append(f"  Input (cached)    : {breakdown.format_token_count(breakdown.total_cached_tokens)}  (cache-hit, discounted)")
    lines.append(f"  Output            : {breakdown.format_token_count(breakdown.total_output_tokens)}")
    lines.append("")

    # --- Cost breakdown ---
    lines.append("Cost Breakdown:")
    lines.append(f"  Input cost    : ${breakdown.input_cost:.4f}  ({breakdown.format_token_count(breakdown.total_input_tokens)} not cached)")
    lines.append(f"  Cache cost    : ${breakdown.cached_cost:.4f}  ({breakdown.format_token_count(breakdown.total_cached_tokens)} cached)")
    lines.append(f"  Output cost   : ${breakdown.output_cost:.4f}  ({breakdown.format_token_count(breakdown.total_output_tokens)} output)")
    lines.append(f"  Total cost    : ${breakdown.total_cost:.4f}")
    lines.append("")

    # --- Cache efficiency ---
    if breakdown.total_input_tokens > 0:
        cache_ratio = breakdown.total_cached_tokens / breakdown.total_input_tokens
        cache_pct = cache_ratio * 100
        lines.append(f"Cache efficiency: {cache_pct:.1f}% of input tokens served from cache")
        lines.append("")

    return "\n".join(lines)


def load_trace(trace_path: str) -> dict[str, Any]:
    """Load and validate a trace JSON file.

    Args:
        trace_path: Path to the trace JSON file.

    Returns:
        Parsed trace data.

    Raises:
        FileNotFoundError: If the file doesn't exist.
        ValueError: If the trace format is invalid.
    """
    path = Path(trace_path)
    if not path.is_file():
        raise FileNotFoundError(f"Trace file not found: {trace_path}")

    raw_text = path.read_text(encoding="utf-8")
    trace_data = json.loads(raw_text)

    # Validate expected structure
    if "request_body" not in trace_data:
        raise ValueError("Trace missing 'request_body' key")
    if "messages" not in trace_data["request_body"]:
        raise ValueError("Trace missing 'request_body.messages' key")

    return trace_data


def main() -> None:
    """Entry point: parse args, load trace, calculate and display cost."""
    import argparse

    parser = argparse.ArgumentParser(description="Estimate token cost of an agent trace with cache-aware pricing.")
    parser.add_argument(
        "trace_path",
        help="Path to the trace JSON file.",
    )
    parser.add_argument(
        "--input-price",
        type=float,
        default=None,
        help="Input token price per 1M tokens (overrides model detection).",
    )
    parser.add_argument(
        "--cache-price",
        type=float,
        default=None,
        help="Cache-hit token price per 1M tokens (overrides model detection).",
    )
    parser.add_argument(
        "--output-price",
        type=float,
        default=None,
        help="Output token price per 1M tokens (overrides model detection).",
    )

    args = parser.parse_args()

    # Load trace
    trace_data = load_trace(args.trace_path)
    messages = trace_data["request_body"]["messages"]
    model = trace_data.get("model") or trace_data.get("last_sse", {}).get("model")
    trace_id = Path(args.trace_path).stem

    # Build pricing config
    if args.input_price is not None and args.cache_price is not None and args.output_price is not None:
        pricing = PricingConfig(
            input_price_per_million=args.input_price,
            cache_price_per_million=args.cache_price,
            output_price_per_million=args.output_price,
        )
    else:
        pricing = _select_pricing_config(model)

    # Calculate cost
    breakdown = _calculate_cost(messages, pricing, model, trace_id)

    # Display results
    output = _format_breakdown(breakdown)
    print(output)


if __name__ == "__main__":
    main()
