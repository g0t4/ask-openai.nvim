#!/usr/bin/env fish
# uv pip install   --index-url https://download.pytorch.org/whl/cu128 torch torchvision torchaudio
# uv pip install flash-attn einops --no-build-isolation --no-deps

# *** 2025-10-23 torch 2.9.0+cu128 IS NOT WORKING (yet)
# - torch2.9.0+cu128 is not working which was released 2025-10-15
# - flash-attn has releases through 2.8 (not 2.9 yet) and it appears they plan on 2.9 landing with CUDA 13.0
# - Approx 2025-08-23 (AUGUST 23?) is when I checked in this file (venv-fix-buil21.fish) w/ flast-attn and einops
#   - found via fish history
#   - FYI cloned repo in Jan 2025 (way before RAG added)
# *** torch==2.8.0 works!
uv sync --extra build21
uv pip install torch==2.8.0
#     * test deps and/or get version info:
python3 -c "import torch; print(torch.version.cuda)"
# 12.8
python3 -c "import flash_attn; print('FlashAttention OK')"
# FlashAttention OK
