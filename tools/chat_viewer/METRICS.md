# Backend statistics

The summary tables use this order: cached tokens, newly processed input,
reasoning/final split where reported, generated output, speculative decoding,
and phase durations. `#1` is the first assistant message, regardless of how many
user/tool messages precede it. Headers can wrap. There are no speed bars.

- llama-server `prompt_n` is **new input**, excluding `cache_n`.
- OpenAI-compatible `usage.prompt_tokens` includes cached tokens. New input is
  `prompt_tokens - prompt_tokens_details.cached_tokens`. An absent cache count
  is unknown, not zero. The per-message display labels inclusive input when
  that is all the server supplied; the summary's new-input cell stays unknown.
- Output includes reasoning. Final output is `completion_tokens - reasoning_tokens`.
  Thinking percentage is reasoning divided by output. The split stays unknown
  when the reasoning count is absent or inconsistent (for example, greater than
  total output). Raw counters are still preserved and visible in message stats.
- vLLM's approximate input rate uses new input / scheduled-to-first-token time.
  Approximate decode rate uses `(output - 1) / first-to-last-token time`.
  These are effective wall-clock phase rates, marked `≈`.
- Durations are seconds with two decimal places. The totals sum new input,
  generated output and phase durations; they do not sum cumulative cached counts
  or average speeds. Thinking percentage in the total row uses aggregate counts.
  Phase totals omit tool execution and other agent overhead.
- Cache continuity uses the previous **total input + generated output** as the
  expected next cached count for each backend, with the existing one-token
  tolerance. This is a continuity heuristic: template changes, discarded reasoning,
  cache-block boundaries and eviction can all produce a `MISS` indication.

For a future optional detail view, consider **TTFT, queue time and mean ITL**.
They are deliberately absent from the summary. vLLM's overall output rate includes
prefill and is not displayed; the verbatim metric remains in the saved trace.

## SGLang OpenAI streaming

Discovery recognizes `owned_by: "sglang"` from `/v1/models`. Requests made through
the model-parameter builder enable `stream_options.include_usage`,
`return_spec_tokens_details`, and `return_cached_tokens_details` for this backend.
Cache reporting also depends on the server's `--enable-cache-report` setting.

SGLang sends `sglext.spec_tokens_details` in an empty-choices chunk, followed by a
separate usage chunk. Both trigger trace capture, and their metadata is merged
without changing the incoming objects. Null placeholders do not erase stats from
an earlier chunk. A normal finish marker also saves a trace if usage is omitted.
Per-assistant messages, top-level `last_sse`, live socket updates,
trace restoration, Python and Svelte viewers retain/display these fields:

| SGLang field | Display |
| --- | --- |
| `usage.prompt_tokens` | Total prompt count; subtract cached for new input |
| `usage.prompt_tokens_details.cached_tokens` | Cached count |
| `usage.completion_tokens` | Generated output, including reasoning |
| `usage.reasoning_tokens` | Reasoning count (SGLang uses a flat usage field) |
| `spec_num_correct_drafts / spec_num_proposed_drafts` | Accepted/proposed draft ratio |
| `spec_accept_rate` | Acceptance percentage, one decimal place |
| `spec_accept_length` | Mean acceptance length |

The complete `sglext` object is saved verbatim, including histograms and cache
breakdowns that do not yet have dedicated display columns. Multi-choice arrays
are preserved without attributing one choice's speculative counters to another.

SGLang's current `/v1/chat/completions` streaming response does **not** expose
server prefill/decode phase durations. Its `return_meta_info` option is rejected
with streaming enabled. Consequently SGLang's duration/rate cells remain unknown;
we do not call end-to-end latency a decode duration or invent a prefill rate.
Existing native `meta_info` counters can also be read by the Python parser.

Verified against the live GLM 5.3 Flash server on 2026-10-23: separate speculative
and usage chunks, and cached prompt counts on a repeated prompt.

Primary implementation references:

- [SGLang streaming response and terminal chunks](https://github.com/sgl-project/sglang/blob/main/python/sglang/srt/entrypoints/openai/serving_chat.py)
- [SGLang usage and extension schemas](https://github.com/sgl-project/sglang/blob/main/python/sglang/srt/entrypoints/openai/protocol.py)
- [SGLang usage accounting](https://github.com/sgl-project/sglang/blob/main/python/sglang/srt/entrypoints/openai/usage_processor.py)
