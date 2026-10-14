"""Simple HTTP TTS server for Qwen3-TTS via llama.cpp's llama-tts.

Runs on a remote GPU machine (build21) and serves WAV audio from text.
Each request shells out to ``llama-tts`` (model stays in HF cache, so
subsequent loads are fast).

Usage (on the GPU host):
    python tts_server.py --host 0.0.0.0 --port 8020

Client:
    curl -X POST http://build21.lan:8020/tts \\
         -H 'Content-Type: application/json' \\
         -d '{"text": "hello there wes"}' > /tmp/out.wav
"""

from __future__ import annotations

import argparse
import io
import json
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

LLAMA_TTS = "/home/wes/repos/github/ggml-org/llama.cpp/build/bin/llama-tts"
HF_MODEL = "ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF"
DEFAULT_SPEAKER_FILE = "/home/wes/repos/github/g0t4/ask-openai.nvim/tools/voiced/voices/wes/wes_ref.wav"


class TTSHandler(BaseHTTPRequestHandler):
    """HTTP handler exposing POST /tts (text -> WAV)."""

    server_version = "Qwen3TTS/1.0"

    def _send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_wav(self, wav_bytes: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(wav_bytes)))
        self.end_headers()
        self.wfile.write(wav_bytes)

    def do_GET(self) -> None:
        """Health check."""
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        """Generate speech from text."""
        if self.path != "/tts":
            self._send_json(404, {"error": "not found"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, ValueError):
            self._send_json(400, {"error": "invalid JSON"})
            return

        text = body.get("text", "").strip()
        lang = body.get("lang", "en")
        speaker_file = body.get("speaker_file")
        if speaker_file is None and Path(DEFAULT_SPEAKER_FILE).exists():
            speaker_file = DEFAULT_SPEAKER_FILE

        if not text:
            self._send_json(400, {"error": "text is required"})
            return

        try:
            wav_bytes = self._generate_wav(text, lang, speaker_file)
            self._send_wav(wav_bytes)
        except subprocess.CalledProcessError as exc:
            self._send_json(
                500,
                {"error": f"llama-tts failed: {exc.stderr.decode() if exc.stderr else str(exc)}"},
            )
        except Exception as exc:
            self._send_json(500, {"error": str(exc)})

    def _generate_wav(
        self,
        text: str,
        lang: str,
        speaker_file: Optional[str],
    ) -> bytes:
        """Run llama-tts and return WAV bytes."""
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            out_path = tmp.name

        cmd = [
            LLAMA_TTS,
            "-hf", HF_MODEL,
            "-p", text,
            "--tts-lang", lang,
            "--output", out_path,
        ]
        if speaker_file:
            cmd.extend(["--tts-speaker-file", speaker_file])

        result = subprocess.run(
            cmd,
            capture_output=True,
            check=True,
            timeout=120,
        )

        try:
            wav_data = Path(out_path).read_bytes()
        finally:
            Path(out_path).unlink(missing_ok=True)

        return wav_data

    def log_message(self, format: str, *args) -> None:
        """Silence default request logging."""
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qwen3-TTS HTTP server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8020)
    parser.add_argument("--model", default=HF_MODEL)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    global HF_MODEL
    HF_MODEL = args.model

    server = ThreadingHTTPServer((args.host, args.port), TTSHandler)
    print(f"Qwen3-TTS server listening on {args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
