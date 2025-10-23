#!/usr/bin/env fish
# uv pip install   --index-url https://download.pytorch.org/whl/cu128 torch torchvision torchaudio
uv pip install flash-attn einops --no-build-isolation --no-deps

# ***! NOW USE THIS:
uv sync --extra build21
