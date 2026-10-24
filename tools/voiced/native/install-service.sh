#!/usr/bin/env bash
# Run on build21 from this checkout. Uses cached weights; downloads nothing.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
llama_dir="${LLAMA_SOURCE:-$HOME/repos/github/ggml-org/llama.cpp}"
build_dir="$HOME/.local/lib/voiced-tts/build-short-chunks"
patched_source="$HOME/.local/lib/voiced-tts/llama-source"
expected_revision=f2cc7282ce0042641df55e0e563b75e824e2b647
model_cache="$HOME/.cache/huggingface/hub/models--ggml-org--Qwen3-TTS-12Hz-1.7B-Base-GGUF"

if [[ -z "${TTS_MODEL:-}" ]]; then
    for model_file in "$model_cache"/snapshots/*/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf; do
        [[ -f "$model_file" ]] && export TTS_MODEL="$model_file" && break
    done
fi
if [[ -z "${TTS_MMPROJ:-}" ]]; then
    for model_file in "$model_cache"/snapshots/*/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf; do
        [[ -f "$model_file" ]] && export TTS_MMPROJ="$model_file" && break
    done
fi
[[ -f "${TTS_MODEL:-}" && -f "${TTS_MMPROJ:-}" ]] || {
    echo 'Set TTS_MODEL and TTS_MMPROJ to existing cached GGUF files.' >&2
    exit 1
}
compiler="$(sed -n 's/^CMAKE_CXX_COMPILER:FILEPATH=//p; s/^CMAKE_CXX_COMPILER:STRING=//p' "$llama_dir/build/CMakeCache.txt")"
[[ "$(git -C "$llama_dir" rev-parse HEAD)" == "$expected_revision" ]] || {
    echo 'The private decoder patch must be revalidated against this llama.cpp revision.' >&2
    exit 1
}
if [[ ! -e "$patched_source/.git" ]]; then
    git -C "$llama_dir" worktree add --detach "$patched_source" "$expected_revision"
fi
[[ "$(git -C "$patched_source" rev-parse HEAD)" == "$expected_revision" ]]
patch_file="$repo_dir/tools/voiced/native/qwen3tts-short-chunks.patch"
if git -C "$patched_source" apply --check "$patch_file" 2>/dev/null; then
    git -C "$patched_source" apply "$patch_file"
else
    # Accept an already-applied patch, but never silently ignore a conflict.
    git -C "$patched_source" apply --reverse --check "$patch_file"
fi
cmake -S "$repo_dir/tools/voiced/native" -B "$build_dir" \
    -DLLAMA_SOURCE="$llama_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER="$compiler" \
    -DVOICED_MTMD_SOURCE="$patched_source"
cmake --build "$build_dir" -j 4
(cd "$repo_dir" && "$repo_dir/.venv/bin/python3" -m tools.voiced.native.check_short_chunks \
    --worker "$build_dir/voiced-tts-worker")

backup_dir="$HOME/.local/lib/voiced-tts/rollback-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$backup_dir" "$HOME/.config/systemd/user"
for config_file in "$HOME/.config/systemd/user/qwen3-tts.service" "$HOME/.config/voiced-tts.env"; do
    [[ ! -f "$config_file" ]] || cp "$config_file" "$backup_dir/"
done
printf 'TTS_MODEL="%s"\nTTS_MMPROJ="%s"\n' "$TTS_MODEL" "$TTS_MMPROJ" > "$HOME/.config/voiced-tts.env"
install -m 755 "$build_dir/voiced-tts-worker" "$HOME/.local/lib/voiced-tts/voiced-tts-worker.new"
mv "$HOME/.local/lib/voiced-tts/voiced-tts-worker.new" "$HOME/.local/lib/voiced-tts/voiced-tts-worker"
cp "$repo_dir/tools/voiced/native/qwen3-tts.service" "$HOME/.config/systemd/user/qwen3-tts.service"
git -C "$llama_dir" rev-parse HEAD > "$HOME/.local/lib/voiced-tts/llama-revision.txt"
systemctl --user daemon-reload
systemctl --user enable qwen3-tts.service
systemctl --user restart qwen3-tts.service
echo "Installed. Previous service configuration: $backup_dir"
echo 'Check readiness: curl --fail http://127.0.0.1:8020/health'
