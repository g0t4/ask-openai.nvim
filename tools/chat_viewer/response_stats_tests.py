"""Exercise the shared CLI/Textual renderer with usage-only and mixed traces."""
from io import StringIO
from rich.console import Console
from tools.chat_viewer import __main__ as viewer
from tools.chat_viewer.timings import parse_timings


def test_usage_metrics_render_per_message_summary_and_trace_fallback(monkeypatch):
    monkeypatch.setattr(viewer, "SHOW_ALL", True)
    response = {
        "role": "assistant", "content": "OK",
        "usage": {"prompt_tokens": 100, "completion_tokens": 20,
                  "prompt_tokens_details": {"cached_tokens": 80}},
        "metrics": {"time_to_first_token_ms": 118.64, "generation_time_ms": 52.29,
                    "tokens_per_second": 11.7},
    }
    output = StringIO()
    viewer.render_trace_to_console(Console(file=output, width=300, color_system=None),
                                   [response], "deepseek-v4.1-flash", parse_timings(response))
    text = output.getvalue()
    assert "overall output: 11.7 tok/s" in text
    assert "TTFT: 118.6 ms" in text
    assert "vLLM assistant timings" in text
    assert "total out tokens" in text
    assert "Assistant Generation Speed" not in text
    # Top-level-only last_sse data uses the same parser and display.
    output = StringIO()
    monkeypatch.setattr(viewer, "_console", Console(file=output, width=160, color_system=None))
    viewer.print_model_info("deepseek-v4.1-flash", parse_timings(response))
    assert "overall output: 11.7 tok/s" in output.getvalue()


def test_mixed_backends_and_missing_cache_render_without_crashing(monkeypatch):
    monkeypatch.setattr(viewer, "SHOW_ALL", False)
    messages = [
        {"role": "assistant", "content": "llama", "timings": {
            "prompt_n": 10, "predicted_n": 2, "prompt_per_second": 100, "predicted_per_second": 50}},
        {"role": "assistant", "content": "vllm", "usage": {
            "prompt_tokens": 10, "completion_tokens": 2}, "metrics": None},
    ]
    output = StringIO()
    viewer.render_trace_to_console(Console(file=output, width=300, color_system=None), messages, None, None)
    text = output.getvalue()
    assert "llama-server assistant timings" in text
    assert "vLLM assistant timings" in text
    assert "MISS" not in text
