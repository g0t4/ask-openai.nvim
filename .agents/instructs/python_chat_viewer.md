---
description: commandline AI chat (thread) viewer written in python, used to review traces from this repo's agent harnesses/tools
---

## Key files:
- <tools/chat_viewer> sub-directory with the code
- <tools/chat_viewer/__main__.py> is the entrypoint + the bulk of the code
- <tools/chat_viewer/timings.py> parses and formats model inference timing stats
- <tools/chat_viewer/timings_tests.py> tests for the timings module
- <tools/chat_viewer/markdown_utils.py> helper for splitting H2 markdown sections
- <tools/chat_viewer/markdown_utils_tests.py> tests for markdown utils
- <tools/chat_viewer/tree_wrapper.py> rich Tree wrapper for building message trees
- <tools/chat_viewer/tree_wrapper_tests.py> tests for tree wrapper

## Test structure:
- Test files use `_tests.py` suffix next to their module (i.e., `foo.py` next to `foo_tests.py`)
- Tests use pytest - run with `python -m pytest tools/chat_viewer/`
- For easily tested code (pytest), prefer to split it out into a tested module going forward

## Usage

- Traces are captured here initially:
  ~/.local/state/nvim/ask-openai/{agents,fim,rewrite}
  - each frontend uses a different top level directory
    - `AgentsFrontend` => `agents` dir
    - `PredictionsFrontend` => `fim` dir
    - `RewriteFrontend` => `rewrite` dir
  - traces are captured and stored with unix timestamp as the prefix for the trace.json file:
    - For example `~/.local/state/nvim/ask-openai/agents/1779949218-trace.json`
    - traces are stored once per model turn (after model sends final response to user's prompt/request)
- I manually decide which ones to share, and move the trace file to this repo
  I share with this public repo: https://github.com/g0t4/datasets
  local checkout: ~/repos/github/g0t4/datasets
  for example, here's a trace from today:
     `~/repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-28_004/1780021404-trace.json`
     note the `agents` directory for AgentsFrontend

- Running the viewer:
  ```bash
  cd tools/chat_viewer
  python __main__.py /path/to/trace.json
  python __main__.py < /path/to/trace.json  # stdin mode
  python __main__.py --all trace.json  # show all content (no exclusions)
  python __main__.py --html trace.json  # export to HTML
  ```

## Trace Format

- Supports two trace formats:
  - `*-trace.json` - full trace with request_body, response_message, last_sse
  - `*-messages.jsonl` - JSONL format, one message per line (no model info/timings)

- Trace data structure:
  - `request_body.messages` - list of messages
  - `request_body.tools` - tool definitions (shown with --all)
  - `response_message` - final assistant response (appended to messages)
  - `last_sse` - last SSE event containing model name and timings

## Message Rendering

Messages are rendered based on role:
- **system/developer** - shown as markdown sections, syntax highlighted (magenta headers)
- **user** - shown as markdown sections if they contain H2 headers, otherwise plain text (green)
- **assistant** - shown as plain text with reasoning_content in italic gray, tool calls expanded (yellow)
- **tool** - rendered via `print_tool_result_message()` (red)
  - Semantic grep matches get their own tree structure
  - RAG matches (JSON with matches array) get their own tree structure
  - MCP tool results get parsed by name

## Tool Call Rendering

Assistant tool calls are expanded in a rich Tree structure:
- `apply_patch` - shows patch as syntax-highlighted diff
- `run_command` / `run_process` - shows bash command with bat syntax highlighting
- `run_in_neovim` - shows Lua code with syntax highlighting
- Other tools - shown as JSON key-value pairs in the tree

## Timing Stats

Model info section (print_model_info) displays multi-line timing stats below model name:
```
Model: ggml-org/gpt-oss-120b-GGUF
cached: 11,702 tokens
in: 342 tokens @ 4,009.5 tok/sec
out: 41 tokens @ 241.6 tok/sec
  draft: 80.8% accepted (101 / 125 tokens)
```

Stats are parsed from `last_sse.timings` in the trace:
- `prompt_n` / `predicted_n` - token counts
- `cache_n` - cached tokens
- `draft_n` / `draft_n_accepted` - speculative decoding stats
- `prompt_per_second` / `predicted_per_second` - speed metrics
- Numbers are humanized with comma separators (e.g., `11,702`)

## Content Exclusions

- `EXCLUDED_CONTENT_HASHES` - list of SHA-256 hashes to exclude by default
- `preapproved_file_patterns` - regex patterns for preapproved file paths (from ~/.config/ask-openai/preapproved.txt)
- `--all` flag shows everything (including excluded content)
- Semantic grep matches are checked against preapproved patterns

## Markdown Processing

- H2 sections (## Header) are extracted and shown as collapsible tree items
- Content can be shown as markdown syntax highlighting or plain text
- Special sections (e.g., "Recent yanks") can have emphasized styling via `emphasize_headings` dict

## FYI

- I have the web chat viewer too at <tools/chat_viewer_web> written with Svelte + Vite
  unless I ask for edits to both viewers, assume I only want edits to the python viewer
