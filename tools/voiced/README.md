# voiced

Push-to-talk speech-to-text daemon for ask-openai, inspired by
[whisper.cpp's `examples/stream`](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/stream.cpp).

It captures your microphone while a push-to-talk key is held, streams the
audio through whisper.cpp for real-time transcription, and exposes a Unix
domain socket for IPC (newline-delimited JSON).

It also includes a **Text-to-Speech** client that talks back using
[Qwen3-TTS](https://huggingface.co/spaces/Qwen/Qwen3-TTS) running on a remote
GPU server (build21.lan) via a resident worker linked to llama.cpp.

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

The systemd user service `qwen3-tts.service` runs `tts_server.py` on port 8020
and owns one persistent native worker (`native/tts_worker.cpp`). The worker
loads the cached Qwen3-TTS Q4_K_M backbone and Q8_0 mmproj once, on GPU 0.
Voice cloning uses `tools/voiced/voices/wes/wes_ref.wav`. Startup silently
synthesizes "Ready." to warm the voice encoder and generation kernels before
opening the HTTP listener; no startup audio is played.

Each **complete** `speak` tool call supplies text to the server. During generation,
the worker decodes every six audio frames while preserving vocoder state. It
sends newly generated samples immediately; the model and projection stay loaded,
and inference state resets between utterances. The HTTP server streams mono,
24 kHz PCM16LE through `/tts/stream` using HTTP chunked transfer encoding. The Mac
client feeds these bytes to a `sounddevice.RawOutputStream` and also saves a WAV
for inspection. HTTP chunks may split audio samples; the client aligns them.

`synthesize()` and `POST /tts` still return a complete WAV. No text or tool-call
argument streaming is involved. The process-local playback lock serializes
foreground and background speech. The server accepts one generation at a time
and returns 429 for overlapping requests from other clients. Disconnects or
worker failures invalidate the worker; the next request reloads it. Interrupted
HTTP audio omits the final chunk so the client reports truncation.

Install/rebuild on build21 (uses its existing llama.cpp libraries and cached
weights, without changing the llama.cpp checkout):

```bash
cd ~/repos/github/g0t4/ask-openai.nvim
bash tools/voiced/native/install-service.sh
```

The installer backs up the existing service configuration under
`~/.local/lib/voiced-tts/rollback-*`, writes cached model paths into
`~/.config/voiced-tts.env`, and enables/restarts the service. Its unit is tracked
in `native/qwen3-tts.service`. The source checkout location can be overridden via
`LLAMA_SOURCE`; cached weight paths via `TTS_MODEL` and `TTS_MMPROJ`.
Validated against llama.cpp `f2cc7282ce0042641df55e0e563b75e824e2b647`:
that API returns cumulative float PCM and flushes buffered codes on `get_output`;
our worker sends only the appended samples. It does not need the newer explicit
streaming API.

**Short-chunk decoder fix:** unmodified llama.cpp at that revision pads every
code2wav batch to its 72-frame attention window. With six real frames it returns
only the corresponding PCM, but saves decoder state after the padded frames.
The next batch therefore resumes from fictitious history. Saved WAVs showed
sharp waveform jumps every 0.48 seconds, independently of playback timing.

`native/qwen3tts-short-chunks.patch` separates actual batch length from attention
window size. The installer creates a detached source worktree at
`~/.local/lib/voiced-tts/llama-source` and statically links its patched mtmd library
into our worker. The original llama.cpp checkout and shared libraries used by
other services are untouched. CUDA llama/ggml libraries are reused, so only mtmd
needs compilation. The installed worker is
`~/.local/lib/voiced-tts/voiced-tts-worker`. Revalidate the patch and rebuild this
worker when upgrading llama.cpp; the installer checks the pinned source revision.

Before installing, `native/check_short_chunks.py` performs a GPU regression with
fixed-seed greedy generation: six-frame and 72-frame decoding must agree within
5% normalized waveform RMS error. On the six-second fixture, the unpatched
decoder measured 48.4%; the patched decoder measured 0.818%, approximately 59x
less error. Both produced exactly 144,000 samples. Small differences remain from
GPU numerics at different graph sizes. This checks decoder chunk invariance;
it does not assert subjective voice quality or rule out playback underruns.

Manual start:

```fish
ssh build21 'systemctl --user restart qwen3-tts.service'
curl --fail http://build21.lan:8020/health
ssh build21 'journalctl --user -u qwen3-tts.service -n 30 --no-pager'
```

The health endpoint reports readiness, worker PID, sample rate and chunk size.
The journal records time to first PCM and total synthesis time. The Mac client
logs time to its first playback write separately (not an acoustic measurement).

Measured on 2026-10-24 with the same 25-word input: the previous subprocess/WAV
service returned its first byte at 2.686 s; the resident worker returned first PCM
at 0.102 s and completed synthesis at 0.976 s for 6.64 s of audio. A separate Mac
playback test reached its first output-device write at 0.519 s. The warmed native
worker used approximately 4.5 GiB of GPU memory. Output durations vary with sampling.

Focused regressions (including a server that refuses to finish generation until
the first client playback write):

```bash
.venv/bin/pytest -q tools/voiced/test_tts_streaming.py
```

## Notes

- The **right Option/Alt** key listener needs macOS Accessibility permission for the process
  running the daemon (grant it to your terminal / the daemon's host app).
  Without it, use `:VoicedStart` / `:VoicedStop` or the socket commands.
- The TTS server needs build21 to be reachable from the mac (`build21.lan`).
- Streaming text/tool-call arguments into TTS is a separate future step; current
  audio streaming starts from the complete text supplied to `speak()`.
