# clankerd

The primary brain daemon for ask-openai. It listens to live/final speech
transcriptions from the `voiced` daemon and takes action using a LangChain
agent with MCP tools:

- **run_process** - shell commands with background support, process status,
  completion notifications
- **run_xonsh** - execute Python + shell through Xonsh
- **delegate** - spawn subagents (optionally background), then
  `delegate_status` / `delegate_stop` to manage them

## Live vs final transcriptions

The agent receives two kinds of transcription events:

- **Live** (`final=false`) - partial, streaming text. The agent MAY act on it if
  confident, but must be ready to change course.
- **Final** (`final=true`) - definitive utterance. The agent should re-evaluate
  any work started from live text, abort wrong-direction work, and proceed
  correctly.

## Run

```fish
.venv/bin/python -m tools.clankerd
```

Requires the `voiced` daemon to be running (for transcriptions) and the
llama-server at `http://paxy.lan:8014` (override via
`CLANKERD_LLAMA_SERVER_URL`).

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
