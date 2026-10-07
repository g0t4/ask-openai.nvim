---
description: nvim AI predictions frontend performs copilot like completions as I type
---

Start with `lua/ask-openai/predictions/frontend.lua`

Uses llama-server on the backend

- First local model was `qwen2.5-coder`
  raw prompt via `/v1/completions`
  works with latest Qwen3.6/3.8 models too
- I settled on automatic context with RAG matches (semantic_grep)
  Qwen3-Embedding-0.6B and Qwen3-Reranker-0.6B models
  + `ask_ls` pygls language server via `vim.lsp` + FAISS for search
  + custom RAG index builder with `.rag` with JSON files per `domain` (domain ~= filetype or ~= extension but can be more than one extension)
  + custom embeddings inference backend (py + torch with messagepack comms)
- Second completions model was `gptoss120b`
  - gptoss doesn't have a native FIM prompt format
  - so, I devised a chat based completions format via `v1/chat/completions`
    it worked so well gptoss quickly became my daily driver
    thinking + FIM is leaps and bounds better
    also gptoss120b is incredbly fast (10,000+ tok/s prefill, 250 tok/s decode)
      b/c of this I include lots of context and lots of code before/after the current line... and still can get subsecond completions :)
    albeit chat completions are less "precise" vs qwen2.5-coder's native FIM
    - i.e. indentation, duplicating cursorline prefix
      mostly can be mitigated with tooling (i.e. strip duplicate cursorline prefix)
    - chat models often wrap their completion in markdown fences (```language ... ``` or `...`)
      => strip the leading ```language (and trailing ```) fence in `Prediction:fim_fixes`
      via `lua/ask-openai/predictions/markdown_strip.lua` (streaming-safe: a leading
      fence is only stripped once newline-terminated; single backticks only when both ends
      wrap; skipped entirely in markdown files where fences are the intended content)
  Config includes a setting to disable reasoning or adjust its effort level.
- in mid 2026 a plethora of capable models emerged that all do very well with the Chat based completions format, notably: Muse Glimmer 30B
