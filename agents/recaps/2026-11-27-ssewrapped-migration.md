# Recap: SSEWrapped migration (sessions 2026-11-27)

## Big-picture goal

Thread an `SSEWrapped` type through the whole SSE path so the raw SSE object
is only touched in the right places, and the handlers can't observe vim.NIL
semantics directly. Push the wrapper upstream into the curl backend.

## Final state (as of last session)

**New module**: `lua/ask-openai/backends/sse_wrapped.lua` — `SSEWrapped` class.
- Ctor `SSEWrapped.new(sse_parsed)` **nil_ifies in place** (deep). All reads
  through the wrapper are vim.NIL-free.
- Methods: `has_choice()` (with the `has_choices() → has_choice()` rename;
  logs a warning with raw data when > 1 choice), `first_choice()`,
  `no_choices()`, `has_error()`, `finish_reason()` (straight `first_choice()`
  now — redundant `vim_NIL_to_nil` removed), `is_finished()`, `model()`,
  `log(message)` (lazy-requires the logger).
- `LuaLS` doc annotations use `LlamaServerSSEBase` + `LlamaServerChatCompletionSSE_Choice`.

**Wrapper creation**: at `backends/curl.lua` `on_one_data_value` (also fake
model servers), right after JSON decode. No frontend creates the wrapper.

**`OnParsedSSE` alias** is now `fun(sse_wrapped: SSEWrapped)`.
`completion_logger.log_sse_to_request` still receives the raw object (same
table, mutated in place by the ctor, so it's nil-safe). Error checks use
`has_error()` (curl + parser). `request.type` used for logging.

**Frontends**:
- `AgentsFrontend.on_parsed_data_sse(sse_wrapped)`: `has_choice()` guard →
  `on_streaming_delta_update_message_history(sse_wrapped, request)` (new
  signature; single wrapper param). Aggregator receives wrapper, unwraps
  internally. `sse_wrapped:model()` for `live_trace_stream.changed`.
- `RewritesFrontend.on_parsed_data_sse(sse_wrapped)`: `first_choice()` guard.
- `PredictionsFrontend.on_parsed_data_sse(sse_wrapped)`: passes wrapper to
  parsers; `on_sse_llama_server_timings` passes `sse_wrapped.sse_parsed`
  through to stats.

**Parsers** (`backends/sse/parsers.lua`): both `parse_sse_v1_chat_completions`
and `parse_sse_llamacpp_completions` take `sse_wrapped`. Chat completions:
`has_error()` → silent `nil` (curl owns error logging/UI), `no_choices()` →
silent `nil`, everything else via the wrapper. Raw completions: unwraps
inside (`---@cast sse_wrapped.sse_parsed LlamaServerRawCompletionSSE`),
still uses raw object for field reads. Removed redundant `vim_NIL_to_nil`
(ctor nil_ifies). Redundant vim.NIL checks on nil-ified delta/logprob/finish_reason
fields removed. Raw-completions finish_reason is now just `sse.stop_type`.

**Logging** (after back-and-forth in-session): only curl logs errors via
`log:error(message)` + `frontend.explain_error(message)` on
`sse_wrapped:has_error()`. Downstream no longer logs SSE raw. The one
wrapper-side log call is `sse_wrapped:log("on_one_data_value[" ..
request.type .. "]")` right after the wrapper is created in the curl path.

**Other decisions**:
- `SSEWrapped:model()` exists as a plain accessor now; if the model ever
  needs to be computed, that's the single seam.
- The error-handling refactor (parsers + curl) is committed but the
  downstream nil-skip semantics (agents `on_streaming_delta_update_message_history`
  aggregator, `response_reasoning.get_content`) is unchanged in shape.

**Test status** (at last check):
- `sse_wrapped.tests.lua` — 7/7 pass.
- `tools/tests/sse.lua` — 8/8 pass.
- `backends/response_reasoning.tests.lua` — 6 pass, 3 pre-existing failures
  (vim.NIL mutation semantics + SGLang metadata-only SSE nil-result path)
  — confirmed present on a clean pre-refactor worktree.
- `agents/fake_model_server.tests.lua` — error at `chat_window:buffer()` in
  `after_each` — also pre-existing (verified on clean HEAD).

## Current task states

Active session: pair-refactoring tooling idea. Idea saved as
`agents/ideas/feature-pair-refactoring.md` (discussed between user and
agent — read it first).

## To resume

1. Read the current diff with `git log --oneline -20`.
2. Check `lua/ask-openai/backends/sse_wrapped.lua` and
   `backends/sse/parsers.lua` for the current shape.
3. If extending the wrapper: ctor nil_ify invariant, `model()`/`first_choice()`
   as the canonical accessors; keep vim.NIL out of callers' data unless they
   are inside the wrapper.
4. The `completion_logger` likely wants the wrapper pushed down eventually
   (it still receives raw). Deferring — it has `~= vim.NIL` checks that should
   be folded in.
5. The accumulator class (`agents/messages/rx.lua`) and `completion_logger`
   were deliberately left unchanged.

## Notes

- The user values small pair-reviewed steps + git revert over big atomic PRs.
- Idea for pairing: in-editor diff view of the last commit; small commits;
  review gates.
