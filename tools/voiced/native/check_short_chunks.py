"""GPU regression: short and full decoder batches must reconstruct the same speech.

Run on build21 with TTS_MODEL/TTS_MMPROJ from ~/.config/voiced-tts.env.
Uses greedy sampling to hold generated speech codes constant across requests.
"""
import argparse
import array
import json
import math
import os
import sys
import time

from tools.voiced.tts_server import DEFAULT_SPEAKER_FILE, TTSWorker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    args = parser.parse_args()
    worker = TTSWorker([
        args.worker, "-m", os.environ["TTS_MODEL"], "-mm", os.environ["TTS_MMPROJ"],
        "-ngl", "99", "-c", "8192", "-n", "512", "-t", "8",
        "--seed", "42", "--top-k", "1", "--temp", "0",
    ])
    results = {}
    metrics = {}
    try:
        worker.start()
        for frames in (6, 72):
            worker.chunk_frames = frames
            started = time.monotonic()
            chunks_out = []
            first = None
            with worker.stream(
                "Wes, this is the streaming audio boundary test. The samples should flow continuously from one chunk into the next.",
                "en", DEFAULT_SPEAKER_FILE,
            ) as (rate, chunks):
                for chunk in chunks:
                    if first is None:
                        first = time.monotonic() - started
                    chunks_out.append(chunk)
            pcm = array.array("h", b"".join(chunks_out))
            if sys.byteorder != "little":
                pcm.byteswap()
            results[frames] = pcm
            metrics[str(frames)] = {
                "samples": len(pcm), "audio_seconds": len(pcm) / rate,
                "first_pcm_seconds": first, "total_seconds": time.monotonic() - started,
                "chunk_samples": [len(chunk) // 2 for chunk in chunks_out],
            }
    finally:
        worker.close()
    short, full = results[6], results[72]
    assert len(short) == len(full) and len(full) > 0, "Generated durations differ"
    rms = math.sqrt(sum(float(x) ** 2 for x in full) / len(full))
    error = math.sqrt(sum(float(a - b) ** 2 for a, b in zip(short, full)) / len(full))
    relative = error / max(rms, 1)
    print(json.dumps({"batches": metrics, "normalized_rms_error": relative}, indent=2))
    # Allows floating-point differences between GPU graph shapes, but catches
    # the padded-state bug (~0.48 on this fixture versus ~0.008 with the fix).
    assert relative < 0.05, f"Chunk decoding diverged: normalized RMS error {relative:.4f}"


if __name__ == "__main__":
    main()
