# clankerd

The primary brain daemon for ask-openai. It listens to live/final speech
transcriptions from the `voiced` daemon and takes action using a LangChain
agent with MCP tools:

- **run_process** - shell commands with background support, process status,
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
`run_process(background=True)`, or `run_xonsh(background=True)`), it can
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
