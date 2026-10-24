"""HTTP TTS with one resident llama.cpp worker and incremental PCM output.

POST /tts returns a complete WAV; POST /tts/stream returns chunked PCM16LE.
Both share the same resident model. Native worker diagnostics go to the journal.
"""
from __future__ import annotations

import argparse
import io
import json
import logging
import select
import struct
import subprocess
import threading
import time
import wave
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

LOG = logging.getLogger("voiced.tts")
DEFAULT_SPEAKER_FILE = "/home/wes/repos/github/g0t4/ask-openai.nvim/tools/voiced/voices/wes/wes_ref.wav"


class BusyError(Exception):
    pass


class TTSWorker:
    """Serialize requests to the resident worker's framed stdout protocol."""

    def __init__(self, command: list[str], chunk_frames: int = 6, timeout: float = 120):
        self.command = command
        self.chunk_frames = chunk_frames
        self.timeout = timeout
        self.lock = threading.Lock()
        self.process = None
        self.sample_rate = None

    @property
    def ready(self):
        return self.process is not None and self.process.poll() is None and self.sample_rate is not None

    def _read(self, size: int) -> bytes:
        result = bytearray()
        deadline = time.monotonic() + self.timeout
        while len(result) < size:
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([self.process.stdout], [], [], left)[0]:
                raise TimeoutError("TTS worker timed out")
            chunk = self.process.stdout.read(size - len(result))
            if not chunk:
                raise RuntimeError("TTS worker exited; see service journal")
            result.extend(chunk)
        return bytes(result)

    def _metadata(self):
        line = bytearray()
        while len(line) < 4096:
            byte = self._read(1)
            if byte == b"\n":
                return json.loads(line)
            line.extend(byte)
        raise RuntimeError("Invalid TTS worker metadata")

    def start(self):
        self.close()
        # Unbuffered pipes: select() must see every unread byte.
        self.process = subprocess.Popen(
            self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0,
        )
        try:
            meta = self._metadata()
            if meta.get("ready") is not True or not isinstance(meta.get("sample_rate"), int):
                raise RuntimeError("Invalid TTS worker startup message")
            self.sample_rate = meta["sample_rate"]
            LOG.info("Resident worker ready: pid=%s rate=%s", self.process.pid, self.sample_rate)
        except BaseException:
            self.close()
            raise

    def close(self):
        self.sample_rate = None
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process.stdin.close()
            self.process.stdout.close()
            self.process = None

    @contextmanager
    def stream(self, text: str, lang: str, speaker_file: str | None):
        if not self.lock.acquire(blocking=False):
            raise BusyError("TTS is speaking; retry after the current utterance")
        complete = False
        try:
            if not self.ready:
                self.start()
            request = {"text": text, "lang": lang, "chunk_frames": self.chunk_frames}
            if speaker_file:
                request["speaker_file"] = speaker_file
            remaining = memoryview((json.dumps(request) + "\n").encode())
            while remaining:
                written = self.process.stdin.write(remaining)
                if not written:
                    raise RuntimeError("TTS worker stdin closed")
                remaining = remaining[written:]
            meta = self._metadata()
            rate = meta.get("sample_rate")
            if rate != self.sample_rate:
                raise RuntimeError("TTS worker sample rate changed")

            def chunks():
                nonlocal complete
                while True:
                    size = struct.unpack("<I", self._read(4))[0]
                    if size == 0:
                        complete = True
                        return
                    if size > 16 * 1024 * 1024 or size % 2:
                        raise RuntimeError("Invalid TTS worker PCM frame")
                    yield self._read(size)

            yield rate, chunks()
        finally:
            # Never reuse a worker with an unread or incomplete response.
            if not complete:
                self.close()
            self.lock.release()


class TTSHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "Qwen3TTS/2.0"

    def _send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path != "/health":
            self._send_json(404, {"error": "not found"})
            return
        worker = self.server.worker
        self._send_json(200 if worker.ready else 503, {
            "status": "ok" if worker.ready else "unavailable",
            "backend": "llama.cpp-resident", "streaming": True,
            "worker_pid": worker.process.pid if worker.process else None,
            "sample_rate": worker.sample_rate, "chunk_frames": worker.chunk_frames,
        })

    def do_POST(self):
        if self.path not in ("/tts", "/tts/stream"):
            self.close_connection = True
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            if not 0 < length <= 65536:
                raise ValueError("body must be between 1 and 65536 bytes")
            body = json.loads(self.rfile.read(length))
            text = body.get("text", "").strip()
            lang = body.get("lang", "en")
            speaker = body.get("speaker_file", self.server.speaker_file)
            if not text or not isinstance(lang, str) or (speaker is not None and not isinstance(speaker, str)):
                raise ValueError("text, lang and speaker_file must be strings")
            if speaker and not Path(speaker).is_file():
                raise ValueError("speaker reference does not exist")
        except (ValueError, TypeError, AttributeError) as error:
            self.close_connection = True
            self._send_json(400, {"error": str(error)})
            return

        started = time.monotonic()
        headers_sent = False
        try:
            with self.server.worker.stream(text, lang, speaker) as (rate, chunks):
                if self.path == "/tts/stream":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("X-Audio-Sample-Rate", str(rate))
                    self.send_header("X-Audio-Format", "s16le")
                    self.send_header("X-Audio-Channels", "1")
                    self.send_header("Transfer-Encoding", "chunked")
                    self.end_headers()
                    headers_sent = True
                    first = True
                    for chunk in chunks:
                        self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                        self.wfile.flush()
                        if first:
                            LOG.info("First HTTP PCM: %.3fs", time.monotonic() - started)
                            first = False
                    self.wfile.write(b"0\r\n\r\n")
                    self.wfile.flush()
                else:
                    output = io.BytesIO()
                    with wave.open(output, "wb") as wav:
                        wav.setnchannels(1)
                        wav.setsampwidth(2)
                        wav.setframerate(rate)
                        for chunk in chunks:
                            wav.writeframesraw(chunk)
                    data = output.getvalue()
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/wav")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    headers_sent = True
                    self.wfile.write(data)
            LOG.info("TTS request complete: %.3fs", time.monotonic() - started)
        except BusyError as error:
            self._send_json(429, {"error": str(error)})
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True
            LOG.info("TTS client disconnected")
        except Exception as error:
            LOG.exception("TTS request failed")
            if headers_sent:
                # Omit the final HTTP chunk so clients detect truncated audio.
                self.close_connection = True
            else:
                self._send_json(500, {"error": str(error)})

    def log_message(self, format, *args):
        LOG.debug(format, *args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8020)
    parser.add_argument("--speaker-file", default=DEFAULT_SPEAKER_FILE)
    parser.add_argument("--chunk-frames", type=int, default=6)
    parser.add_argument("--warmup-text", default="Ready.", help="Synthesize silently before accepting requests; empty disables")
    parser.add_argument("--worker", required=True)
    parser.add_argument("worker_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not 1 <= args.chunk_frames <= 72:
        parser.error("--chunk-frames must be between 1 and 72")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    worker_args = args.worker_args
    if worker_args[:1] == ["--"]:
        worker_args = worker_args[1:]
    worker = TTSWorker([args.worker, *worker_args], args.chunk_frames)
    try:
        worker.start()
        if args.warmup_text:
            with worker.stream(args.warmup_text, "en", args.speaker_file) as (_, chunks):
                for _ in chunks:
                    pass
            LOG.info("Voice encoder and generation warmup complete")
        server = ThreadingHTTPServer((args.host, args.port), TTSHandler)
        server.daemon_threads = True
        server.worker = worker
        server.speaker_file = args.speaker_file
        LOG.info("TTS listening on %s:%s", args.host, args.port)
        try:
            server.serve_forever()
        finally:
            server.server_close()
    finally:
        worker.close()


if __name__ == "__main__":
    main()
