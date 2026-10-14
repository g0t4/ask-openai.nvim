"""Client for the Qwen3-TTS HTTP server.

Connects to a remote TTS server (default: build21.lan:8020), sends text,
receives WAV audio, and plays it on the local machine.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

import httpx

from tools.voiced.config import state_dir


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
        """Synthesize speech and play it, returning the temp WAV path."""
        wav_bytes = self.synthesize(text, lang=lang, speaker_file=speaker_file)

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp_path = Path(tmp.name)
        tmp.write(wav_bytes)
        tmp.close()

        subprocess.run(["afplay", str(tmp_path)], check=True)
        return tmp_path


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
