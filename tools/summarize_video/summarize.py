"""Core logic for summarizing a video with a vision-capable llama-server model.

The video is transcoded (downscaled + fps capped) before being sent to the model
because llama-server tokenizes each decoded frame, and a full-resolution video
can easily blow past the context window (we saw ~363k tokens for a 4K clip).
"""

import base64
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import httpx
import numpy as np

from tools.voiced.transcriber import Transcriber

DEFAULT_BASE_URL = "http://build21.lan:8016"
DEFAULT_MODEL = None  # auto-detect from /v1/models
DEFAULT_PROMPT = (
    "You are a video summarizer. Watch the attached video and provide a concise "
    "summary of what happens, including the setting, people, actions, and any "
    "on-screen text or notable details. Keep it to a few sentences."
)
DEFAULT_AUDIO_PROMPT = (
    "Below is the transcript of a video's audio track. Summarize what was said, "
    "including the speaker, the key topics, and any notable points. Keep it concise."
)
DEFAULT_MAX_TOKENS = 600
DEFAULT_WIDTH = 640
DEFAULT_FPS = 2.0
DEFAULT_MAX_FRAMES = 64
DEFAULT_TEMPERATURE = 0.2
DEFAULT_WHISPER_MODEL = str(
    Path.home()
    / "Library"
    / "Application Support"
    / "pywhispercpp"
    / "models"
    / "ggml-large-v3-turbo.bin"
)
DEFAULT_WHISPER_THREADS = 4


def find_model(base_url: str = DEFAULT_BASE_URL) -> str:
    """Query llama-server's OpenAI-compatible endpoint for the active model id."""
    response = httpx.get(f"{base_url}/v1/models", timeout=10)
    response.raise_for_status()
    data = response.json()
    model_id = data.get("model") or (data.get("data", [{}])[0].get("id"))
    if not model_id:
        raise RuntimeError(f"Could not determine a model id from {base_url}/v1/models")
    return model_id


def probe_duration(path: Path) -> float:
    """Return the video duration in seconds, or 0.0 if it cannot be probed."""
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return float(result.stdout.strip())
    except Exception:
        return 0.0


def transcode_video(
    src: Path,
    dest: Path,
    width: int = DEFAULT_WIDTH,
    fps: float = DEFAULT_FPS,
    max_frames: int = DEFAULT_MAX_FRAMES,
) -> Path:
    """Downscale and cap the frame rate so the video fits in the model's context.

    Writes an h264 MP4 (no audio) to ``dest`` and returns it.
    """
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg is required but not found on PATH")
    if not src.exists():
        raise FileNotFoundError(src)

    duration = probe_duration(src)
    target_fps = fps
    if duration > 0 and max_frames > 0:
        target_fps = min(target_fps, max_frames / duration)

    filter_args = f"scale={width}:-2,fps={target_fps}"
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(src),
        "-vf", filter_args,
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-an",
        str(dest),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr.strip()}")
    return dest


def extract_audio(src: Path, dest_wav: Path) -> Path:
    """Extract the audio track as mono 16 kHz WAV."""
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg is required but not found on PATH")
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(src),
        "-vn",
        "-ac", "1",
        "-ar", "16000",
        "-c:a", "pcm_s16le",
        str(dest_wav),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed to extract audio: {result.stderr.strip()}")
    return dest_wav


def transcribe_audio(
    wav_path: Path,
    whisper_model_path: str = DEFAULT_WHISPER_MODEL,
    n_threads: int = DEFAULT_WHISPER_THREADS,
) -> str:
    """Transcribe a mono 16 kHz WAV file to text via whisper.cpp."""
    model_path = Path(whisper_model_path)
    if not model_path.exists():
        raise FileNotFoundError(
            f"Whisper model not found at {model_path}. Pass --whisper-model."
        )
    with wave.open(str(wav_path), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
    audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    transcriber = Transcriber(str(model_path), n_threads=n_threads)
    transcript = transcriber.transcribe(audio)
    if not transcript:
        raise RuntimeError("No speech detected in the audio track")
    return transcript


def _post_chat(
    base_url: str,
    model_id: str,
    content_parts: list[dict],
    prompt: str,
    max_tokens: int,
    temperature: float,
) -> str:
    """Send a chat completion request and return the assistant's text."""
    payload = {
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": prompt}, *content_parts],
            }
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    response = httpx.post(
        f"{base_url}/v1/chat/completions",
        json=payload,
        timeout=600,
    )
    response.raise_for_status()
    data = response.json()
    return data["choices"][0]["message"]["content"].strip()


def summarize_video(
    video_path: Path,
    base_url: str = DEFAULT_BASE_URL,
    model: str | None = DEFAULT_MODEL,
    prompt: str = DEFAULT_PROMPT,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    width: int = DEFAULT_WIDTH,
    fps: float = DEFAULT_FPS,
    max_frames: int = DEFAULT_MAX_FRAMES,
    temperature: float = DEFAULT_TEMPERATURE,
    audio_only: bool = False,
    whisper_model_path: str = DEFAULT_WHISPER_MODEL,
    whisper_threads: int = DEFAULT_WHISPER_THREADS,
) -> str:
    """Summarize a video and return the model's text response.

    When ``audio_only`` is True, the audio track is transcribed with whisper.cpp
    and the transcript (instead of video frames) is summarized. This is needed
    because llama-server reports ``audio: false`` for the multimodal model.
    """
    video_path = video_path.resolve()
    if not video_path.exists():
        raise FileNotFoundError(video_path)

    model_id = model or find_model(base_url)

    if audio_only:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav_path = Path(tmp.name)
        try:
            extract_audio(video_path, wav_path)
            transcript = transcribe_audio(wav_path, whisper_model_path, whisper_threads)
        finally:
            wav_path.unlink(missing_ok=True)
        return _post_chat(
            base_url,
            model_id,
            [{"type": "text", "text": f"Audio transcript:\n{transcript}"}],
            DEFAULT_AUDIO_PROMPT,
            max_tokens,
            temperature,
        )

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        transcode_video(video_path, tmp_path, width, fps, max_frames)
        encoded = base64.b64encode(tmp_path.read_bytes()).decode()
    finally:
        tmp_path.unlink(missing_ok=True)

    content_parts = [
        {
            "type": "video_url",
            "video_url": {"url": f"data:video/mp4;base64,{encoded}"},
        }
    ]
    return _post_chat(base_url, model_id, content_parts, prompt, max_tokens, temperature)
