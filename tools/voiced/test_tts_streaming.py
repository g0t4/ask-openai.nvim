"""Streaming protocol regressions; no model or audio hardware required."""
import io
import sys
import struct
import threading
import types
import wave
from contextlib import contextmanager
from http.server import ThreadingHTTPServer

import httpx
import pytest

from tools.voiced.tts import TTSClient
from tools.voiced.tts_server import TTSHandler, TTSWorker


@contextmanager
def server(worker):
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), TTSHandler)
    httpd.daemon_threads = True
    httpd.worker = worker
    httpd.speaker_file = None
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield httpd.server_port
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join()


def test_playback_begins_before_generation_finishes(monkeypatch):
    played = threading.Event()
    frames = []

    class Worker:
        @contextmanager
        def stream(self, *args):
            def chunks():
                yield b"\x01\x00" * 100
                # Server cannot finish generation until client plays first PCM.
                assert played.wait(3), "client buffered until generation finished"
                yield b"\x02\x00" * 100
            yield 24000, chunks()

    class Output:
        def __init__(self, **kwargs):
            assert kwargs["samplerate"] == 24000
            assert kwargs["dtype"] == "int16"

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def write(self, data):
            frames.append(bytes(data))
            played.set()
            return False

    monkeypatch.setitem(sys.modules, "sounddevice", types.SimpleNamespace(RawOutputStream=Output))
    with server(Worker()) as port:
        path = TTSClient("127.0.0.1", port).speak("test")
    try:
        with wave.open(str(path)) as wav:
            data = wav.readframes(wav.getnframes())
            assert data == b"".join(frames)
            # A delayed next segment may insert silence while keeping the same
            # output device open. No speech samples may be dropped or replayed.
            assert [x for (x,) in struct.iter_unpack("<h", data) if x] == [1] * 100 + [2] * 100
    finally:
        path.unlink()


def test_worker_reuses_process_and_recovers_from_abandoned_stream(tmp_path):
    script = tmp_path / "worker.py"
    script.write_text('''
import json, struct, sys
out = sys.stdout.buffer
out.write(b'{"ready":true,"sample_rate":24000}\\n'); out.flush()
for line in sys.stdin:
    json.loads(line)
    out.write(b'{"sample_rate":24000}\\n')
    for chunk in (b'\\x01\\x00' * 100, b'\\x02\\x00' * 100):
        out.write(struct.pack('<I',len(chunk)) + chunk); out.flush()
    out.write(struct.pack('<I',0)); out.flush()
''')
    worker = TTSWorker([sys.executable, str(script)], timeout=3)
    try:
        worker.start()
        original = worker.process.pid
        for _ in range(2):
            with worker.stream("test", "en", None) as (rate, chunks):
                assert rate == 24000
                assert len(b"".join(chunks)) == 400
            assert worker.process.pid == original
        with worker.stream("test", "en", None) as (_, chunks):
            assert next(chunks)
            # Abandon response; pending bytes must not enter the next utterance.
        assert not worker.ready
        with worker.stream("test", "en", None) as (_, chunks):
            assert len(b"".join(chunks)) == 400
        assert worker.process.pid != original
    finally:
        worker.close()


def test_truncated_worker_response_fails_and_closes_worker(tmp_path):
    script = tmp_path / "broken.py"
    script.write_text('''
import sys, struct
out=sys.stdout.buffer
out.write(b'{"ready":true,"sample_rate":24000}\\n'); out.flush()
sys.stdin.readline()
out.write(b'{"sample_rate":24000}\\n'+struct.pack('<I',100)+b'xx'); out.flush()
''')
    worker = TTSWorker([sys.executable, str(script)], timeout=3)
    with pytest.raises(RuntimeError, match="worker exited"):
        with worker.stream("test", "en", None) as (_, chunks):
            list(chunks)
    assert not worker.ready


def test_legacy_wav_endpoint_and_bad_requests():
    class Worker:
        @contextmanager
        def stream(self, *args):
            yield 24000, iter([b"\x00\x01" * 100])

    with server(Worker()) as port:
        base = f"http://127.0.0.1:{port}"
        response = httpx.post(base + "/tts", json={"text": "test"})
        assert response.status_code == 200
        with wave.open(io.BytesIO(response.content)) as wav:
            assert wav.getframerate() == 24000
            assert wav.getnframes() == 100
        for body in ({"text": ""}, {"text": 123}, [], {"text": "x", "speaker_file": "/missing.wav"}):
            assert httpx.post(base + "/tts", json=body).status_code == 400


def test_client_aligns_split_samples_and_rejects_truncation(monkeypatch, tmp_path):
    import tools.voiced.tts as tts

    class Response:
        headers = {"X-Audio-Sample-Rate": "24000", "X-Audio-Format": "s16le", "X-Audio-Channels": "1"}
        pieces = [b"\x01", b"\x00\x02", b"\x00"]

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def raise_for_status(self):
            pass

        def iter_bytes(self):
            return iter(self.pieces)

    writes = []

    class Output:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def write(self, data):
            assert len(data) % 2 == 0
            writes.append(data)
            return False

    monkeypatch.setitem(sys.modules, "sounddevice", types.SimpleNamespace(RawOutputStream=Output))
    monkeypatch.setattr(tts.tempfile, "tempdir", str(tmp_path))
    monkeypatch.setattr(tts.httpx, "stream", lambda *a, **kw: Response())
    path = TTSClient().speak("test")
    assert b"".join(writes) == b"\x01\x00\x02\x00"
    path.unlink()
    Response.pieces = [b"\x01\x00\x02"]
    with pytest.raises(ValueError, match="incomplete or empty"):
        TTSClient().speak("test")
    assert list(tmp_path.iterdir()) == []


def test_segments_prefetch_next_request_and_keep_one_output_stream(monkeypatch):
    second_requested = threading.Event()
    requests = []
    outputs = []
    played = []

    class Worker:
        @contextmanager
        def stream(self, text, *args):
            requests.append(text)
            if len(requests) == 2:
                second_requested.set()
            yield 24000, iter([bytes([len(requests), 0]) * 100])

    class Output:
        def __init__(self, **kwargs):
            outputs.append(self)

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def write(self, data):
            played.append(data)
            assert second_requested.wait(2), "next synthesis waited for playback to finish"
            return False

    monkeypatch.setitem(sys.modules, "sounddevice", types.SimpleNamespace(RawOutputStream=Output))
    with server(Worker()) as port:
        path = TTSClient("127.0.0.1", port).speak_segments(["First.", "Second."])
    try:
        assert requests == ["First.", "Second."]
        assert len(outputs) == 1
        assert [x for (x,) in struct.iter_unpack("<h", b"".join(played)) if x] == [1] * 100 + [2] * 100
    finally:
        path.unlink()


def test_cancel_segment_stream_stops_player_and_removes_partial_wav(monkeypatch, tmp_path):
    import tools.voiced.tts as tts
    stop = threading.Event()

    class Worker:
        @contextmanager
        def stream(self, *args):
            yield 24000, iter([b"\x01\x00" * 100])

    class Output:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def write(self, data):
            stop.set()
            return False

    def segments():
        yield "First."
        while not stop.wait(.01):
            pass

    monkeypatch.setitem(sys.modules, "sounddevice", types.SimpleNamespace(RawOutputStream=Output))
    monkeypatch.setattr(tts.tempfile, "tempdir", str(tmp_path))
    with server(Worker()) as port, pytest.raises(tts.SpeechCancelled):
        TTSClient("127.0.0.1", port).speak_segments(segments(), stop_event=stop)
    assert list(tmp_path.iterdir()) == []
