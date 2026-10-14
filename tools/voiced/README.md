# voiced

Push-to-talk speech-to-text daemon for ask-openai, inspired by
[whisper.cpp's `examples/stream`](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/stream.cpp).

It captures your microphone while a push-to-talk key is held, streams the
audio through whisper.cpp for real-time transcription, and exposes a Unix
domain socket for IPC (newline-delimited JSON).

It also includes a **Text-to-Speech** client that talks back using
[Qwen3-TTS](https://huggingface.co/spaces/Qwen/Qwen3-TTS) running on a remote
GPU server (build21.lan) via `llama-tts` from llama.cpp.

## What it does

- **PTT** - hold the **right Option/Alt** key on macOS to talk (detected via a Quartz
  `CGEventTap`). While held, audio is captured and transcribed live. On
  release, a final transcription of the whole utterance is emitted.
  (Socket-based `start` / `stop` commands work as a fallback.)
- **Low latency** - whisper.cpp stays loaded in memory (via `pywhispercpp`);
  transcriptions stream every `--step-ms` while listening.
- **Unix socket** - `~/.local/state/ask-openai/voiced.sock`, newline-delimited
  JSON both directions.
- **Logging** - transcriptions and daemon events are appended to
  `~/.local/state/ask-openai/voiced.log`.
- **TTS (speech output)** - generates speech from text using Qwen3-TTS with
  voice cloning support. The TTS server runs on `build21.lan:8020` as a
  systemd user service.

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

## Text-to-Speech (TTS)

The TTS client connects to the Qwen3-TTS HTTP server on `build21.lan:8020`
(managed by the `qwen3-tts` systemd user service).

### Quick test

```fish
.venv/bin/python -m tools.voiced.test_tts
```

### Client API

```python
from tools.voiced.tts import speak, synthesize, TTSClient, SERVER_VOICE_REF

# Speak with Wes's cloned voice
speak("hello there wes", speaker_file=SERVER_VOICE_REF)

# Or via the client
client = TTSClient()
client.speak("hello there wes", speaker_file=SERVER_VOICE_REF)
```

### TTS server (on build21)

The server is a systemd user service (`qwen3-tts.service`) that runs
`tools/voiced/tts_server.py` on port 8020. It shells out to `llama-tts`
(llama.cpp's TTS tool) with the `ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF`
model. Voice cloning uses a speaker reference file (Wes's voice is at
`tools/voiced/voices/wes/wes_ref.wav`).

Manual start:

```fish
ssh build21 'systemctl --user restart qwen3-tts.service'
```

## Notes

- The **right Option/Alt** key listener needs macOS Accessibility permission for the process
  running the daemon (grant it to your terminal / the daemon's host app).
  Without it, use `:VoicedStart` / `:VoicedStop` or the socket commands.
- The TTS server needs build21 to be reachable from the mac (`build21.lan`).
- This is a proof of concept. VAD (e.g. Silero), feeding transcriptions
  into the AI prompt, and real-time streaming TTS are natural next steps.
