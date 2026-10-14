"""Test Qwen3-TTS: say "hello there wes" with Wes's cloned voice.

Usage:
    python -m tools.voiced.test_tts

Prerequisites:
    - Qwen3-TTS server running on build21.lan:8020 (see tts_server.py)
    - The mac can reach build21.lan
    - Reference voice audio at tools/voiced/voices/wes/wes_ref.wav
"""

from __future__ import annotations

import sys

from tools.voiced.tts import DEFAULT_VOICE_REF, SERVER_VOICE_REF, TTSClient


def main() -> int:
    client = TTSClient()

    print("Checking TTS server health...")
    if not client.health():
        print("ERROR: TTS server unreachable. Is it running on build21.lan:8020?")
        return 1
    print("Server is up.")

    if DEFAULT_VOICE_REF.exists():
        print(f"Using cloned voice from: {DEFAULT_VOICE_REF}")
    else:
        print("WARNING: No voice reference found, using default speaker")

    text = "hello there wes"
    print(f"Synthesizing: {text!r}")

    tmp_path = client.speak(
        text,
        speaker_file=SERVER_VOICE_REF if DEFAULT_VOICE_REF.exists() else None,
    )
    print(f"Played audio from: {tmp_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
