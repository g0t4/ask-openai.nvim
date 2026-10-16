"""Energy-based voice activity detection (VAD) for hands-free activation.

Monitors a rolling window of mic audio while idle. When speech onset is
detected (sustained loud frames), it signals "start"; when speech ends
(sustained quiet frames), it signals "stop". Pure numpy — no extra deps.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np

from tools.voiced.config import SAMPLE_RATE


def rms(frame: np.ndarray) -> float:
    """Root-mean-square level of a float32 frame."""
    if frame.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(frame))))


@dataclass
class VadConfig:
    sample_rate: int = SAMPLE_RATE
    frame_ms: int = 30            # analysis frame length
    start_threshold: float = 0.035  # RMS level considered "voice" on onset
    stop_threshold: float = 0.020   # RMS below this counts as silence
    start_frames: int = 4          # consecutive loud frames to trigger start
    stop_frames: int = 10          # consecutive quiet frames to trigger stop
    max_idle_ms: int = 12000       # force-stop after this much continuous speech
    rearm_frames: int = 8          # quiet frames required after force-stop to re-arm
    min_speech_ms: int = 300       # ignore blips shorter than this


class VoiceActivityDetector:
    """State machine that emits start/stop events based on mic energy."""

    def __init__(self, config: Optional[VadConfig] = None) -> None:
        self.cfg = config or VadConfig()
        self._frame_size = int(self.cfg.sample_rate * self.cfg.frame_ms / 1000.0)
        self._loud_run = 0
        self._quiet_run = 0
        self._in_speech = False
        self._speech_frames = 0   # cumulative loud frames while in speech
        self._cooldown = 0        # frames of quiet required after force-stop

    def feed(self, samples: np.ndarray) -> Optional[str]:
        """Feed a chunk of mono float32 audio; returns 'start'/'stop'/None."""
        out: Optional[str] = None
        for i in range(0, len(samples) - self._frame_size + 1, self._frame_size):
            frame = samples[i:i + self._frame_size]
            level = rms(frame)
            if self._in_speech:
                if level >= self.cfg.start_threshold:
                    self._speech_frames += 1
                    self._quiet_run = 0
                    if self._speech_frames * self.cfg.frame_ms > self.cfg.max_idle_ms:
                        self._in_speech = False
                        self._cooldown = self.cfg.rearm_frames
                        out = "stop"
                else:
                    self._quiet_run += 1
                    if self._quiet_run >= self.cfg.stop_frames:
                        self._in_speech = False
                        self._quiet_run = 0
                        out = "stop"
            else:
                # Only quiet frames consume the force-stop cooldown, so a
                # re-arm genuinely requires a moment of silence.
                if level < self.cfg.start_threshold and self._cooldown > 0:
                    self._cooldown -= 1
                    continue
                if self._cooldown > 0:
                    continue
                if level >= self.cfg.start_threshold:
                    self._loud_run += 1
                    if self._loud_run >= self.cfg.start_frames:
                        self._in_speech = True
                        self._speech_frames = 0
                        self._quiet_run = 0
                        out = "start"
                else:
                    self._loud_run = 0
        return out

    @property
    def in_speech(self) -> bool:
        return self._in_speech
