# clankerd

The primary brain daemon for ask-openai. It listens to live/final speech
transcriptions from the `voiced` daemon and takes action using a LangChain
agent with MCP tools:

- **run_bash** - shell commands with background support, process status,
  completion notifications
- **run_xonsh** - execute Python + shell through Xonsh
- **delegate** - spawn subagents (optionally background), then
  `delegate_status` / `delegate_stop` to manage them
- **speak** - text-to-speech with the user's cloned voice (Qwen3-TTS)

## Live vs final transcriptions

The agent receives two kinds of transcription events:

- **Live** (`final=false`) - partial, streaming text. The daemon broadcasts
  these for display but **never triggers agent runs**. This prevents parallel
  agent executions and duplicate responses.
- **Final** (`final=true`) - definitive utterance. The daemon cancels any
  in-flight agent run and starts a fresh one. This is the only time the
  agent is invoked.

## Single chain of thought

Clankerd behaves like a single person with one chain of thought:
- It responds to an inquiry once and doesn't repeat itself.
- If a new final transcription arrives while it's working, the message is
  **queued** and delivered at the next opportunity (after the current run
  completes). This prevents parallel agents while preserving follow-ups.
- When it needs time to think or do research, it fires a "one sec" speech
  notification (background speak) so the user knows it's working.
- It doesn't respond to trivial fragments like "you" or "thank you" with
  long-winded responses.

## Queueing

Follow-up final transcriptions that arrive while the agent is busy are
queued in the daemon. After the current agent run completes, queued messages
are delivered as sequential follow-up runs. This means:
- Your follow-up is never lost.
- The agent processes your first request to completion, then handles the
  follow-up.
- No parallel agent runs ever happen.

## Background tasks & rest

When clanker fires off a background task (`delegate(background=True)`,
`run_bash(background=True)`, or `run_xonsh(background=True)`), it can
rest — it doesn't need to poll. When the task completes, a
`background/done` notification triggers a new agent turn with the result
as context. This keeps clanker responsive to new voice input.

## Run

```fish
.venv/bin/python -m tools.clankerd
```

Requires the `voiced` daemon to be running (for transcriptions) and the
llama-server at `http://paxy.lan:8014` (override via
`CLANKERD_LLAMA_SERVER_URL`).

`speak` plays streamed PCM from the resident Qwen3-TTS service on build21.
Clankerd keeps its local tool when an MCP server exports the same name; this
ensures playback runs in clankerd's Mac environment rather than an MCP venv.

## Streaming speak arguments

Clankerd observes `on_chat_model_stream` tool-call deltas. A handler specific to
`speak` decodes stable prefixes of the JSON `text` string, including fragmented
escapes and Unicode surrogate pairs. It releases punctuated sentences as they
arrive and flushes a final unpunctuated tail when the string closes. Common
abbreviations and decimal points are kept together. This is a boundary heuristic,
not a linguistic sentence parser.

Each tool-call ID owns one speech session. Calls enter a FIFO; each session
contains a text-segment queue. One producer synthesizes segments sequentially
while a player consumes a bounded PCM queue through one output device stream.
Prefetch is limited to twelve 4096-sample packets (about two seconds at 24 kHz).
If text or audio stalls, the player sends silence and records a waiting/resumed
event. It does not close and reopen the audio device between sentences.

The normal LangGraph `speak` execution receives its injected tool-call ID and
joins this same session. It validates the final text/language against the streamed
prefix and never resubmits the full text. Foreground calls wait for playback;
background calls return after their remaining text is queued. Cancellation stops
queued segments and playback; an in-flight HTTP read remains subject to its read
timeout. Audio already heard cannot be retracted if a later argument is invalid.
Deduplication covers a live session; the in-memory queue is not a durable replay
ledger across process restarts.

Language must be known before early speech starts. By default, language is dynamic:
if a provider sends `text` before `lang`, speech waits for the language field, or
for completed arguments to supply the English default. The current DeepSeek
endpoint was observed to emit text first despite ordering instructions. Setting
`CLANKERD_SPEECH_LANGUAGE=en` fixes the language for the session and constrains the
model's speech tool schema to English; sentences can then start without waiting
for a trailing language field. Other fixed language codes can be configured the
same way. This setting deliberately disables per-call language switching.

- `CLANKERD_STREAM_SPEECH=0`: disable argument interception for whole-call comparison.
- `CLANKERD_SPEECH_BOUNDARY=sentence`: default; `clause` also splits at commas, colons and semicolons.
- `CLANKERD_SPEECH_LANGUAGE=en`: optional fixed language; unset permits dynamic language.

Each segment is a separate TTS request, retaining the loaded model and cloned
voice but resetting its linguistic/prosodic context. Sentence boundaries are the
default quality compromise; this does not implement continuous text input into
one TTS generation context.

Trace files contain `speech_stream_started`, `speech_segment_ready`,
`speech_synthesis_started`, `speech_first_pcm`, `speech_playback_started`,
waiting/resumed, underrun, cancellation, and playback-finished events keyed by
tool-call ID. Synthesis-finished means the client drained that segment's audio;
bounded prefetch can delay that event relative to actual GPU completion.

A live DeepSeek/ToolNode/TTS test with pinned English received the first sentence
at 0.949 s and its first PCM at 1.189 s, before tool arguments completed at
1.491 s. The first audio-device write was at 1.634 s: device startup is a separate
cost, so first PCM and audible-start latency must not be conflated. The six
sentences played once through one output stream, and final ToolNode execution
joined the already-running session. These are one-run timings, not a benchmark.

Tests use an isolated state directory so socket tests cannot replace live sockets:

```bash
XDG_STATE_HOME="$(mktemp -d)" .venv/bin/pytest -q \
    tools/clankerd/test_speech_stream.py tools/clankerd/test_tool_names.py \
    tools/voiced/test_tts_streaming.py
```

## Supervisor

Use the `clankersupervisor` to manage both daemons (voiced + clankerd) as
child processes with auto-restart on crash:

```fish
# Start the supervisor (starts both daemons)
.venv/bin/python -m tools.clankersupervisor

# Control from another shell
.venv/bin/python -m tools.clankersupervisor.client status
.venv/bin/python -m tools.clankersupervisor.client restart-clankerd
.venv/bin/python -m tools.clankersupervisor.client restart-voiced
.venv/bin/python -m tools.clankersupervisor.client restart-all
.venv/bin/python -m tools.clankersupervisor.client stop-clankerd
```

Clankerd can also restart itself via the `restart_daemon` tool:
`restart_daemon('clankerd')`. Its conversation thread is persisted in
SQLite (`~/.local/state/ask-openai/clankerd-thread.db`), so it resumes
where it left off after restart.

## Control socket

The daemon listens on `~/.local/state/ask-openai/clankerd.sock` (newline-
delimited JSON):

```json
{"type": "ping"}
{"type": "status"}
{"type": "message", "text": "hello clankerd", "final": true}
{"type": "shutdown"}
```

Events broadcast to connected clients:

```json
{"type": "pong", "status": "idle"}
{"type": "status", "state": "listening"}
{"type": "transcription", "text": "...", "final": false}
{"type": "agent_response", "text": "...", "final": false}
```

## Logs & traces

- Logs: `~/.local/state/ask-openai/clankerd.log`
- Traces: `~/.local/state/ask-openai/clankerd-traces/` (JSONL per session)
