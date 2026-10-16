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

- **Live** (`final=false`) - partial, streaming text. The daemon is very
  conservative about triggering on these. It only starts an agent run if the
  text is meaningful (≥15 chars), the agent is idle, and it's not a minor
  extension of a previous live transcription. The agent is instructed to
  treat live transcriptions as noise and only respond if extremely confident.
- **Final** (`final=true`) - definitive utterance. The daemon always cancels
  any in-flight agent run and starts a fresh one. The agent treats this as a
  new person speaking to it and responds accordingly.

## Single chain of thought

Clankerd behaves like a single person with one chain of thought:
- It responds to an inquiry once and doesn't repeat itself.
- If interrupted (a new final transcription arrives), it stops and reacts to
  the new input.
- When it needs time to think or do research, it fires a "one sec" speech
  notification (background speak) so the user knows it's working.
- It doesn't respond to trivial fragments like "you" or "thank you" with
  long-winded responses.

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
