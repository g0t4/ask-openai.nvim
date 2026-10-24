"""Client for the Qwen3-TTS HTTP server.

Connects to a remote TTS server (default: build21.lan:8020), sends text,
and plays streamed PCM on the local machine. File synthesis still returns WAV.
"""

from __future__ import annotations

import logging
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
        """Play PCM as it arrives; also save a complete WAV for inspection."""
        import sounddevice as sd

        payload = {"text": text, "lang": lang}
        if speaker_file:
            payload["speaker_file"] = speaker_file
        # Background acknowledgments and foreground speech share the output device.
        with _PLAYBACK_LOCK:
            started = time.monotonic()
            tmp_path = None
            try:
                with httpx.stream(
                    "POST", f"{self._base_url}/tts/stream", json=payload,
                    timeout=self._timeout,
                ) as response:
                    response.raise_for_status()
                    if response.headers.get("X-Audio-Format") != "s16le" or response.headers.get("X-Audio-Channels") != "1":
                        raise ValueError("Expected mono PCM16LE from TTS server")
                    rate = int(response.headers["X-Audio-Sample-Rate"])
                    if not 8000 <= rate <= 192000:
                        raise ValueError("Invalid TTS sample rate")
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                        tmp_path = Path(tmp.name)
                    with wave.open(str(tmp_path), "wb") as wav, sd.RawOutputStream(
                        samplerate=rate, channels=1, dtype="int16", latency="low",
                    ) as audio:
                        wav.setnchannels(1)
                        wav.setsampwidth(2)
                        wav.setframerate(rate)
                        pending = b""
                        first = True
                        for chunk in response.iter_bytes():
                            # HTTP boundaries can split a 16-bit sample.
                            data = pending + chunk
                            aligned = len(data) & ~1
                            pending = data[aligned:]
                            if not aligned:
                                continue
                            data = data[:aligned]
                            wav.writeframesraw(data)
                            if first:
                                LOG.info("TTS first playback write: %.3fs", time.monotonic() - started)
                                first = False
                            if audio.write(data):
                                LOG.warning("TTS playback underrun")
                        if pending or first:
                            raise ValueError("TTS returned incomplete or empty PCM")
                        # RawOutputStream.__exit__ stops and drains queued samples.
                LOG.info("TTS playback complete: %.3fs", time.monotonic() - started)
                return tmp_path
            except BaseException:
                if tmp_path is not None:
                    tmp_path.unlink(missing_ok=True)
                raise


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
