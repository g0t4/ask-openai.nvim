---
description: web-based chat (thread) viewer written with Svelte + Vite + Tailwind, used to review traces from this repo's agent harnesses/tools
---

## Key files:
- <tools/chat_viewer_web> sub-directory with the code
- <tools/chat_viewer_web/index.html> is the HTML entrypoint (just loads the Svelte app)
- <tools/chat_viewer_web/src/main.ts> boots the Svelte app
- <tools/chat_viewer_web/src/App.svelte> is the root component + bulk of the orchestration logic
  - handles URL params, loading traces, directory detection, message rendering
- <tools/chat_viewer_web/src/lib/types.ts> TypeScript interfaces for trace data
- <tools/chat_viewer_web/src/lib/hash-nav.ts> hash navigation utilities for deep linking
- <tools/chat_viewer_web/src/lib/timestamp-utils.ts> timestamp extraction and formatting
- <tools/chat_viewer_web/src/lib/patch-parser.ts> custom patch format parser (word diff)

## Components (Svelte):
- `components/MessageView.svelte` - renders individual messages based on role
- `components/ModelInfo.svelte` - displays model name + timing stats (cached, in/out speed, draft)
- `components/ToolCalls.svelte` - renders assistant tool call blocks with code highlighting
- `components/ToolResult.svelte` - renders tool results (RAG matches, MCP messages, etc.)
- `components/Markdown.svelte` - markdown rendering with toggle between raw and rendered
- `components/SemanticGrepMatches.svelte` - renders semantic grep match output
- `components/CodeBlock.svelte` - syntax highlighted code blocks (via highlight.js)
- `components/ApplyPatch.svelte` - renders patch hunks with word-level diff
- `components/LinkButton.svelte` - copy-to-clipboard link button with # anchor
- `components/FimPreview.svelte` - FIM trace diff preview (green = completion)
- `components/RewritePreview.svelte` - AskRewrite diff preview (red/green = changes)
- `components/GitHubBrowser.svelte` - directory browser for GitHub-hosted traces
- `components/LocalBrowser.svelte` - directory browser for local traces (dev-only)
- `components/FileBrowser.svelte` - generic file browser for URL-based traces

## Styling & Tooling:
- Tailwind CSS for utility classes (configured in <tools/chat_viewer_web/tailwind.config.js>)
- highlight.js for syntax highlighting (github-dark theme)
- marked for markdown parsing
- diff library for word-level diffs

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

- The web viewer loads traces from multiple sources via URL params:
  - `?github=owner/repo/branch/path` - loads from jsDelivr CDN (production)
  - `?local=relative/path` - loads from local filesystem (dev-only, requires Vite dev server)
  - `?url=https://example.com/file.json` - legacy support for direct URLs (files only)
  - Directory URLs (ending with `/` or no extension) trigger directory browser instead of file viewer

- Running locally:
  ```bash
  cd tools/chat_viewer_web
  npm run dev  # starts Vite dev server on port 5173
  ```
  Then visit `http://localhost:5173?local=semantic_grep_auto_context/fims`

## Trace Format

- Supports two trace formats:
  - `*-trace.json` - full trace with request_body, response_message, last_sse
  - `*-messages.jsonl` - JSONL format, one message per line (no model info/timings)

- Trace data structure (types.ts):
  - `TraceJson` - main interface with request_body, response_message, last_sse
  - `Message` - role, content (string or ContentObject), tool_calls, reasoning_content
  - `LastSSE` - contains model name and timings object
  - `Timings` - prompt_n, predicted_n, cache_n, draft_n, draft_n_accepted, speeds

## Message Rendering

Messages are rendered based on role:
- **system/developer** - shown as markdown (styled magenta/cyan headers)
- **user** - shown as markdown if it looks like markdown, otherwise plain text (green)
- **assistant** - shown as markdown with reasoning_content in italic gray (yellow)
- **tool** - rendered specially via ToolResult component (red)
  - Semantic grep matches get their own component
  - RAG matches (JSON with matches array) get their own component
  - MCP tool results get parsed and displayed by name

## Tool Call Rendering

Assistant tool calls are rendered via `ToolCalls.svelte`:
- `apply_patch` - uses ApplyPatch component with word-level diff
- `run_command` / `run_process` - shows bash command with toggle between pretty and raw JSON
- Other tools - shown as JSON code block
- Each tool call gets a copyable anchor link (#msg-tool-n)

## Timing Stats

Model info box (ModelInfo.svelte) displays multi-line timing stats:
```
cached: 11,702 tokens
in: 342 tokens @ 4,009.5 tok/sec
out: 41 tokens @ 241.6 tok/sec
  draft: 80.8% accepted (101 / 125 tokens)
```

- Shows cached tokens, inbound/outbound speeds with comma-separated numbers
- Shows draft acceptance rate for speculative decoding / MTP models
- Only shown when trace has last_sse.timings data

## Hash Navigation

Deep linking into trace messages and sub-elements:
- `#3` - scroll to message 3
- `#3-tool-1` - scroll to message 3, tool call 1
- `#3-match-2` - scroll to message 3, RAG match 2
- `#3-file-1` - scroll to message 3, patch file 1
- Click any message header or tool call to copy the anchor link to clipboard
- Hash changes automatically scroll and highlight the target element

## Directory Browsing

- GitHubBrowser - loads directory listings from jsDelivr CDN
- LocalBrowser - loads directory listings from Vite dev server API (dev-only)
- FileBrowser - generic file browser for URL-based traces
- Directory detection is heuristic-based:
  - Ends with `/` => directory
  - No file extension => directory (e.g., `2026-01-19_002`)
  - Has extension => file (e.g., `.json`, `.txt`)

## FYI

- I have the Python chat viewer too at <tools/chat_viewer>
  unless I ask for edits to both viewers, assume I only want edits to the web viewer
- The web viewer is designed to be deployed to GitHub Pages (base path configured in vite.config.ts)
- Local file serving during dev uses a custom Vite plugin (vite-plugins/local-directory-listing.ts)
