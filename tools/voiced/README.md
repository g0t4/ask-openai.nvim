# voiced

Push-to-talk speech-to-text daemon for ask-openai, inspired by
[whisper.cpp's `examples/stream`](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/stream.cpp).

It captures your microphone while a push-to-talk key is held, streams the
audio through whisper.cpp for real-time transcription, and exposes a Unix
domain socket for IPC (newline-delimited JSON).

## What it does

- **PTT** - hold the **fn** key on macOS to talk (detected via a Quartz
  `CGEventTap`). While held, audio is captured and transcribed live. On
  release, a final transcription of the whole utterance is emitted.
  (Socket-based `start` / `stop` commands work as a fallback.)
- **Low latency** - whisper.cpp stays loaded in memory (via `pywhispercpp`);
  transcriptions stream every `--step-ms` while listening.
- **Unix socket** - `~/.local/state/ask-openai/voiced.sock`, newline-delimited
  JSON both directions.
- **Logging** - transcriptions and daemon events are appended to
  `~/.local/state/ask-openai/voiced.log`.

## Run the daemon

```fish
./start-voiced.fish
# or
.venv/bin/python -m tools.voiced --model <path-to-ggml-model.bin>
```

The default model is
`~/Library/Application Support/pywhispercpp/models/ggml-large-v3-turbo.bin`.
Override with `--model`. Other options: `--threads`, `--step-ms`,
`--max-length-ms`, `--device`.

## IPC protocol

Commands (client -> daemon), one JSON object per line:

```json
{"type": "ping"}
{"type": "start"}
{"type": "stop"}
{"type": "press"}
{"type": "release"}
{"type": "shutdown"}
```

Events (daemon -> client), one JSON object per line:

```json
{"type": "pong"}
{"type": "status", "state": "listening"}
{"type": "transcription", "text": "hello world", "final": false}
{"type": "transcription", "text": "hello world", "final": true}
{"type": "error", "message": "..."}
```

## Neovim client

`require("ask-openai.voiced").setup()` is wired into the plugin's `setup()`.
It connects to the daemon socket and prints incoming transcriptions (and logs
them via the devtools universal logger).

Useful commands:

```vim
:VoicedStart  " start listening
:VoicedStop   " stop listening
:VoicedStatus " ping the daemon
```

## Notes

- The **fn** key listener needs macOS Accessibility permission for the process
  running the daemon (grant it to your terminal / the daemon's host app).
  Without it, use `:VoicedStart` / `:VoicedStop` or the socket commands.
- This is a proof of concept. VAD (e.g. Silero) and feeding transcriptions
  into the AI prompt are natural next steps.

