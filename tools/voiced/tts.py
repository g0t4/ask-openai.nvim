"""Client for the Qwen3-TTS HTTP server.

Connects to a remote TTS server (default: build21.lan:8020), sends text,
and plays streamed PCM on the local machine. File synthesis still returns WAV.
"""

from __future__ import annotations

import logging
import queue
import tempfile
import threading
import time
import wave
from pathlib import Path
from typing import Optional

import httpx

LOG = logging.getLogger(__name__)
_PLAYBACK_LOCK = threading.Lock()
DEFAULT_TTS_HOST = "build21.lan"
DEFAULT_TTS_PORT = 8020

# Default voice reference (Wes's voice) for cloning
DEFAULT_VOICE_DIR = Path(__file__).parent / "voices" / "wes"
DEFAULT_VOICE_REF = DEFAULT_VOICE_DIR / "wes_ref.wav"
# On the remote server, this is the path to the same reference
SERVER_VOICE_REF = "/home/wes/repos/github/g0t4/ask-openai.nvim/tools/voiced/voices/wes/wes_ref.wav"


class SpeechCancelled(Exception):
    """The owner cancelled a queued or playing speech operation."""


class TTSClient:
    """Client for the Qwen3-TTS HTTP server."""

    def __init__(
        self,
        host: str = DEFAULT_TTS_HOST,
        port: int = DEFAULT_TTS_PORT,
        timeout: float = 30.0,
    ) -> None:
        self._base_url = f"http://{host}:{port}"
        self._timeout = timeout

    def health(self) -> bool:
        """Check if the TTS server is reachable."""
        try:
            resp = httpx.get(f"{self._base_url}/health", timeout=5.0)
            return resp.status_code == 200
        except httpx.HTTPError:
            return False

    def synthesize(
        self,
        text: str,
        lang: str = "en",
        speaker_file: Optional[str] = None,
    ) -> bytes:
        """Send text to the TTS server and return WAV bytes."""
        payload = {"text": text, "lang": lang}
        if speaker_file:
            payload["speaker_file"] = speaker_file

        resp = httpx.post(
            f"{self._base_url}/tts",
            json=payload,
            timeout=self._timeout,
        )
        resp.raise_for_status()
        return resp.content

    def speak(
        self,
        text: str,
        lang: str = "en",
        speaker_file: Optional[str] = None,
    ) -> Path:
        """Play one utterance through the same queued player used for segments."""
        return self.speak_segments([text], lang=lang, speaker_file=speaker_file)

    def speak_segments(
        self, segments, lang="en", speaker_file=None, *, stop_event=None, on_event=None,
    ) -> Path:
        """Synthesize sequential text segments ahead of one continuous player.

        The producer can prepare the next sentence during playback. PCM is split
        into at most 4096-sample packets; twelve queued packets bound prefetch to
        about two seconds at 24 kHz. Silence fills genuine text/network gaps.
        """
        import sounddevice as sd

        stop = stop_event if stop_event is not None else threading.Event()
        packets = queue.Queue(maxsize=12)
        started = time.monotonic()

        def event(name, **fields):
            if on_event:
                on_event(name, elapsed=time.monotonic() - started, **fields)

        def put(packet):
            while not stop.is_set():
                try:
                    packets.put(packet, timeout=0.05)
                    return True
                except queue.Full:
                    pass
            return False

        def produce():
            rate = None
            try:
                for index, text in enumerate(segments):
                    if stop.is_set():
                        return
                    if not text.strip():
                        continue
                    payload = {"text": text, "lang": lang}
                    if speaker_file:
                        payload["speaker_file"] = speaker_file
                    event("synthesis_started", segment=index)
                    with httpx.stream(
                        "POST", f"{self._base_url}/tts/stream", json=payload,
                        timeout=self._timeout,
                    ) as response:
                        response.raise_for_status()
                        if response.headers.get("X-Audio-Format") != "s16le" or response.headers.get("X-Audio-Channels") != "1":
                            raise ValueError("Expected mono PCM16LE from TTS server")
                        current_rate = int(response.headers["X-Audio-Sample-Rate"])
                        if not 8000 <= current_rate <= 192000 or (rate is not None and rate != current_rate):
                            raise ValueError("Invalid or changed TTS sample rate")
                        rate = current_rate
                        pending = b""
                        first = True
                        for chunk in response.iter_bytes():
                            if stop.is_set():
                                return
                            data = pending + chunk
                            aligned = len(data) & ~1
                            pending = data[aligned:]
                            data = data[:aligned]
                            if data and first:
                                event("first_pcm", segment=index)
                                first = False
                            for offset in range(0, len(data), 8192):
                                if not put((rate, data[offset:offset + 8192])):
                                    return
                        if pending or first:
                            raise ValueError("TTS returned incomplete or empty PCM")
                    event("synthesis_finished", segment=index)
                put(None)
            except Exception as error:
                put(error)

        with _PLAYBACK_LOCK:
            if stop.is_set():
                raise SpeechCancelled("Speech cancelled before playback")
            producer = threading.Thread(target=produce, name="tts-prefetch", daemon=True)
            producer.start()
            tmp_path = None
            try:
                while True:
                    if stop.is_set():
                        raise SpeechCancelled("Speech cancelled")
                    try:
                        packet = packets.get(timeout=0.05)
                        break
                    except queue.Empty:
                        pass
                if isinstance(packet, Exception):
                    raise packet
                if packet is None:
                    raise ValueError("TTS returned incomplete or empty PCM")
                rate, data = packet
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    tmp_path = Path(tmp.name)
                with wave.open(str(tmp_path), "wb") as wav, sd.RawOutputStream(
                    samplerate=rate, channels=1, dtype="int16", latency="low",
                ) as audio:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(rate)
                    event("playback_started")
                    LOG.info("TTS first playback write: %.3fs", time.monotonic() - started)
                    gap = False
                    while True:
                        if stop.is_set():
                            raise SpeechCancelled("Speech cancelled")
                        wav.writeframesraw(data)
                        if audio.write(data):
                            event("playback_underrun")
                            LOG.warning("TTS playback underrun")
                        try:
                            packet = packets.get_nowait()
                        except queue.Empty:
                            # Keep the device clock running if the next sentence
                            # is still arriving. Do not restart the output device.
                            if not gap:
                                event("playback_waiting")
                            gap = True
                            data = bytes(max(1, rate // 50) * 2)  # 20 ms silence
                            continue
                        if isinstance(packet, Exception):
                            raise packet
                        if packet is None:
                            break
                        if gap:
                            event("playback_resumed")
                            gap = False
                        _, data = packet
                event("playback_finished")
                LOG.info("TTS playback complete: %.3fs", time.monotonic() - started)
                return tmp_path
            except BaseException:
                if tmp_path is not None:
                    tmp_path.unlink(missing_ok=True)
                raise
            finally:
                stop.set()
                # The segment iterator must honor stop_event. HTTP reads retain
                # their timeout; cancellation is checked between received chunks.
                producer.join(timeout=self._timeout + 1)


def speak(
    text: str,
    lang: str = "en",
    speaker_file: Optional[str] = None,
) -> Path:
    """Convenience one-shot: synthesize text and play it."""
    client = TTSClient()
    if speaker_file is None and DEFAULT_VOICE_REF.exists():
        speaker_file = SERVER_VOICE_REF
    return client.speak(text, lang=lang, speaker_file=speaker_file)


def synthesize(
    text: str,
    lang: str = "en",
    speaker_file: Optional[str] = None,
) -> Path:
    """Convenience one-shot: synthesize text to a WAV file (no playback)."""
    client = TTSClient()
    if speaker_file is None and DEFAULT_VOICE_REF.exists():
        speaker_file = SERVER_VOICE_REF
    wav_bytes = client.synthesize(text, lang=lang, speaker_file=speaker_file)

    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp_path = Path(tmp.name)
    tmp.write(wav_bytes)
    tmp.close()
    return tmp_path
