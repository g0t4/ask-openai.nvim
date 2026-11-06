"""Tests for the video summarizer.

Unit tests exercise the transcoding pipeline locally.
The end-to-end test is an integration test that calls the live llama-server and
skips automatically when the server (or the sample video) is unavailable.

Usage:
    pytest tools/summarize_video/tests -v
"""

from pathlib import Path

import httpx
import pytest

from tools.summarize_video.summarize import (
    DEFAULT_BASE_URL,
    DEFAULT_WHISPER_MODEL,
    extract_audio,
    find_model,
    probe_duration,
    summarize_video,
    transcode_video,
    transcribe_audio,
)

SAMPLE_VIDEO = Path(__file__).resolve().parents[1] / "video" / "video1.mkv"


def _server_available(base_url: str = DEFAULT_BASE_URL) -> bool:
    try:
        response = httpx.get(f"{base_url}/health", timeout=5)
        return response.status_code == 200
    except Exception:
        return False


def test_probe_duration_positive():
    assert probe_duration(SAMPLE_VIDEO) > 0


def test_transcode_video_produces_small_file(tmp_path):
    dest = tmp_path / "small.mp4"
    transcode_video(SAMPLE_VIDEO, dest, width=320, fps=1, max_frames=32)
    assert dest.exists()
    assert dest.stat().st_size > 0
    assert dest.stat().st_size < SAMPLE_VIDEO.stat().st_size


def test_transcode_video_missing_source(tmp_path):
    with pytest.raises(FileNotFoundError):
        transcode_video(tmp_path / "nope.mkv", tmp_path / "out.mp4")


def test_extract_audio_produces_wav(tmp_path):
    wav_path = tmp_path / "audio.wav"
    extract_audio(SAMPLE_VIDEO, wav_path)
    assert wav_path.exists()
    assert wav_path.stat().st_size > 0


@pytest.mark.integration
def test_find_model_returns_id():
    if not _server_available():
        pytest.skip("llama-server not reachable")
    model_id = find_model()
    assert model_id


@pytest.mark.integration
def test_summarize_video_end_to_end():
    if not SAMPLE_VIDEO.exists():
        pytest.skip("sample video not present")
    if not _server_available():
        pytest.skip("llama-server not reachable")

    result = summarize_video(
        SAMPLE_VIDEO,
        max_tokens=300,
        width=320,
        fps=1,
        max_frames=32,
    )
    assert result, "summarize_video returned an empty result"
    assert len(result) > 20, "summary is suspiciously short"


@pytest.mark.integration
def test_summarize_video_audio_only():
    if not SAMPLE_VIDEO.exists():
        pytest.skip("sample video not present")
    if not _server_available():
        pytest.skip("llama-server not reachable")
    if not Path(DEFAULT_WHISPER_MODEL).exists():
        pytest.skip("whisper model not present")

    result = summarize_video(
        SAMPLE_VIDEO,
        audio_only=True,
        max_tokens=300,
    )
    assert result, "audio-only summarize returned an empty result"
    assert len(result) > 20, "audio-only summary is suspiciously short"
