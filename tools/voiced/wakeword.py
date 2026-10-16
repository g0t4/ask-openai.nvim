"""Voice-activated push-to-talk.

Listens continuously on the microphone and drives the existing `voiced` PTT
socket with verbal cues, so you don't have to hold down the right Option key:

  * Say  "clanker, clanker"  (or "clinker, clinker")  ->  PTT press  (start listening)
  * Say  "over" / "out" / "copy"                       ->  PTT release (stop listening)

This is a separate always-on listener using a small, fast whisper model
(ggml-tiny.en) so it can run continuously at low CPU. When it fires, it sends
`press` / `release` over the voiced Unix socket, which the existing `voiced`
daemon already understands. That daemon then captures audio with the larger
turbo model and streams transcriptions to `clankerd`.

Run with:  python -m tools.voiced.wakeword
"""

from __future__ import annotations

import argparse
import json
import re
import socket
import threading
import time
from typing import Optional

import numpy as np
import sounddevice as sd

from tools.voiced.config import SAMPLE_RATE, socket_path
from tools.voiced.transcriber import Transcriber
from tools.voiced.voiced_logger import get_logger

logger = get_logger(__name__)

# Default model: small & fast so continuous listening is cheap.
DEFAULT_WAKE_MODEL = str(
    __import__("pathlib").Path.home()
    / "Library"
    / "Application Support"
    / "pywhispercpp"
    / "models"
    / "ggml-tiny.en.bin"
)

# Keyword patterns (case-insensitive, fuzzy on the wake word).
WAKE_RE = re.compile(r"\b(?:clanker|clinker)\b(?:\s*,\s*\b(?:clanker|clinker)\b)?", re.I)
RELEASE_RE = re.compile(r"\b(?:over|out|copy|break\s*break)\b", re.I)

# Rolling audio window (seconds) fed to the tiny model each tick.
WINDOW_SECONDS = 2.0
# How often (seconds) we re-transcribe the window.
TICK_SECONDS = 1.0
# Cooldown (seconds) after firing so we don't re-trigger on the same utterance.
COOLDOWN_SECONDS = 2.5


class WakeWordPTT:
    """Continuously listens for wake/release keywords and drives the voiced PTT."""

    def __init__(
        self,
        model_path: str,
        device: Optional[int] = None,
        tick: float = TICK_SECONDS,
        window: float = WINDOW_SECONDS,
    ) -> None:
        self._transcriber = Transcriber(model_path, n_threads=4)
        self._device = device
        self._tick = tick
        self._window_samples = int(window * SAMPLE_RATE)
        self._buffer: np.ndarray = np.zeros((0,), dtype=np.float32)
        self._lock = threading.Lock()
        self._pressed = False
        self._last_fire = 0.0
        self._stream: Optional[sd.InputStream] = None
        self._stop = threading.Event()

    # ------------------------------------------------------------- mic capture

    def _audio_callback(self, indata, frames, time_info, status) -> None:
        with self._lock:
            self._buffer = np.concatenate((self._buffer, indata[:, 0]))
            if len(self._buffer) > self._window_samples:
                self._buffer = self._buffer[-self._window_samples:]

    def start(self) -> None:
        self._stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            callback=self._audio_callback,
            device=self._device,
        )
        self._stream.start()
        logger.info("wake-word mic started (device=%s)", self._device)

    def stop(self) -> None:
        self._stop.set()
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

    # ----------------------------------------------------------- keyword logic

    def _detect(self, text: str) -> Optional[str]:
        """Return 'press', 'release', or None based on the transcribed text."""
        if RELEASE_RE.search(text):
            return "release"
        if WAKE_RE.search(text):
            return "press"
        return None

    def _send(self, command: str) -> bool:
        """Send a press/release command to the voiced socket. Returns success."""
        path = socket_path()
        if not path.exists():
            logger.warning("voiced socket missing at %s", path)
            return False
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(2.0)
            sock.connect(str(path))
            sock.sendall((json.dumps({"type": command}) + "\n").encode("utf-8"))
            sock.close()
            logger.info("sent %r to voiced socket", command)
            return True
        except Exception as error:
            logger.warning("failed to send %r to voiced: %s", command, error)
            return False

    def _fire(self, command: str) -> None:
        now = time.monotonic()
        if now - self._last_fire < COOLDOWN_SECONDS:
            logger.debug("cooldown; ignoring %r", command)
            return
        self._last_fire = now
        self._send(command)
        if command == "press":
            self._pressed = True
        elif command == "release":
            self._pressed = False

    # ------------------------------------------------------------------ loop

    def run(self) -> None:
        self.start()
        try:
            while not self._stop.is_set():
                with self._lock:
                    audio = self._buffer.copy()
                if audio.size < SAMPLE_RATE:  # need at least ~1s to say anything
                    time.sleep(self._tick)
                    continue
                text = self._transcriber.transcribe(audio)
                action = self._detect(text)
                if action:
                    logger.info("wakeword %r -> %r (text=%r)", action, action, text)
                    self._fire(action)
                time.sleep(self._tick)
        finally:
            self.stop()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="wakeword",
        description="Voice-activated push-to-talk for the voiced daemon.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_WAKE_MODEL,
        help="path to a small whisper.cpp model for keyword spotting",
    )
    parser.add_argument("--device", type=int, default=None, help="input device index")
    parser.add_argument("--tick", type=float, default=TICK_SECONDS, help="transcribe interval (s)")
    parser.add_argument("--window", type=float, default=WINDOW_SECONDS, help="audio window (s)")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    wake = WakeWordPTT(model_path=args.model, device=args.device, tick=args.tick, window=args.window)
    logger.info("wake-word PTT starting (model=%s)", args.model)
    try:
        wake.run()
    except KeyboardInterrupt:
        logger.info("wake-word PTT stopped")


if __name__ == "__main__":
    main()
