"""Tests for the energy-based voice activity detector."""

from __future__ import annotations

import numpy as np

from tools.voiced.config import SAMPLE_RATE
from tools.voiced.vad import VadConfig, VoiceActivityDetector, rms


def _tone(dur_ms: float, amp: float, rate: int = SAMPLE_RATE) -> np.ndarray:
    n = int(rate * dur_ms / 1000.0)
    t = np.arange(n) / rate
    return (amp * np.sin(2 * np.pi * 440 * t)).astype(np.float32)


def test_rms_level():
    assert rms(np.zeros(100, dtype=np.float32)) == 0.0
    loud = _tone(100, 0.5)
    assert rms(loud) > 0.3
    quiet = _tone(100, 0.005)
    assert rms(quiet) < 0.01


def test_vad_triggers_start_and_stop():
    cfg = VadConfig(start_threshold=0.05, stop_threshold=0.01, start_frames=3, stop_frames=4)
    vad = VoiceActivityDetector(cfg)
    assert vad.feed(np.zeros(SAMPLE_RATE // 2, dtype=np.float32)) is None
    assert vad.feed(_tone(600, 0.4)) == "start"
    assert vad.in_speech
    assert vad.feed(np.zeros(SAMPLE_RATE, dtype=np.float32)) == "stop"
    assert not vad.in_speech


def test_vad_ignores_short_blip():
    cfg = VadConfig(start_threshold=0.05, stop_threshold=0.01, start_frames=6, stop_frames=4)
    vad = VoiceActivityDetector(cfg)
    assert vad.feed(_tone(50, 0.5)) is None
    assert not vad.in_speech


def test_vad_max_idle_force_stop():
    cfg = VadConfig(start_threshold=0.05, stop_threshold=0.01, start_frames=2,
                    stop_frames=4, max_idle_ms=200, rearm_frames=8)
    vad = VoiceActivityDetector(cfg)
    # Feed short speech chunk to trigger a start without exceeding max_idle.
    assert vad.feed(_tone(120, 0.4)) == "start"
    assert vad.in_speech
    # Feed continued loud audio -> force-stop after max_idle_ms.
    assert vad.feed(_tone(300, 0.4)) == "stop"
    assert not vad.in_speech


def test_vad_requires_rearm_after_force_stop():
    cfg = VadConfig(start_threshold=0.05, stop_threshold=0.01, start_frames=2,
                    stop_frames=4, max_idle_ms=200, rearm_frames=8)
    vad = VoiceActivityDetector(cfg)
    assert vad.feed(_tone(120, 0.4)) == "start"
    assert vad.feed(_tone(300, 0.4)) == "stop"
    # Immediately loud again: should NOT re-trigger until enough quiet frames.
    assert vad.feed(_tone(200, 0.4)) is None
    assert not vad.in_speech
    # After quiet re-arm, speech can trigger again.
    assert vad.feed(np.zeros(SAMPLE_RATE, dtype=np.float32)) is None
    assert vad.feed(_tone(120, 0.4)) == "start"
