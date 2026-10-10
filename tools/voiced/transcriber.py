"""Streaming transcription via whisper.cpp (pywhispercpp wrapper)."""

from __future__ import annotations

import numpy as np
from pywhispercpp.model import Model


class Transcriber:
    """Wraps a loaded whisper.cpp model and transcribes float32 PCM."""

    def __init__(self, model_path: str, n_threads: int = 4) -> None:
        self._model = Model(model_path, n_threads=n_threads)

    def transcribe(self, audio: np.ndarray) -> str:
        """Transcribe mono float32 PCM (16kHz) and return joined text."""
        if audio.size == 0:
            return ""
        segments = self._model.transcribe(
            audio,
            single_segment=True,
            no_timestamps=True,
            print_progress=False,
            print_realtime=False,
        )
        return " ".join(segment.text for segment in segments).strip()

