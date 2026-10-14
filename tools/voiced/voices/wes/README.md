# Wes's voice reference

Reference clip extracted from `recording.mkv` (2026-05 qwen3.6).

## Transcript

"Little video I want to make. I've been tinkering around with Qwen 3.6, and I took
the opportunity just to trust to see what it would do with some of the coding that
I was"

## Usage

For `llama-tts` voice cloning (no transcript needed):
```fish
llama-tts -hf ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF \
    -p "hello there wes" \
    --tts-lang en \
    --tts-speaker-file tools/voiced/voices/wes/wes_ref.wav \
    --output /tmp/out.wav
```

For the `qwen_tts` Python package (needs transcript):
```python
from qwen_tts import Qwen3TTSModel
model = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-Base")
wavs, sr = model.generate_voice_clone(
    text="hello there wes",
    language="English",
    ref_audio="tools/voiced/voices/wes/wes_ref.wav",
    ref_text="Little video I want to make. I've been tinkering around with Qwen 3.6, and I took the opportunity just to trust to see what it would do with some of the coding that I was",
)
```
