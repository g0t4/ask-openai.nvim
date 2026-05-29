---
description: commandline AI chat (thread) viewer written in python, used to review traces from this repo's agent harnesses/tools
---

## Key files:
- <tools/chat_viewer> sub-directory with the code
- <tools/chat_viewer/__main__.py> is the entrypoint + the bulk of the code
- there are some libraries next to __main__.py that have tests with them
  - test file right next to code i.e. `foo.py` next to `foo_tests.py`
    use `_tests.py` suffix for new test files
  - for easily tested code (pytest) I would prefer to split it out into a tested module going forward

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

## FYI

- I have other viewers too, note the web chat viewer <tools/chat_viewer_web> written with vite
  unless I ask for edits to both viewers, assume I only want edits to the python viewer
