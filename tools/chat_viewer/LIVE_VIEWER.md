# Live agent viewer

Run the usual `view_trace --watch` (or `python -m tools.chat_viewer.live_viewer`).
After Neovim loads the updated plugin, the next agent request starts a local Unix
socket automatically. The viewer discovers it alongside the saved trace files.
No port, extra service, or configuration is required.

The viewer shows role, reasoning, content, and tool arguments while a response is
in progress. Reasoning and content remain separate; partial text and arguments
are literal, with no Markdown interpretation or JSON parsing. Completed messages
switch to the normal renderer, including tool formatting and response statistics.
Tool results use the same flattened messages as the model and saved traces.

Socket updates are coalesced to at most 20 per second and terminal redraws to
10 per second. Unchanged message widgets are retained. The initial connection
receives the current history and any partial response; later updates replace only
the changed suffix. Disconnecting and reconnecting gets a fresh full snapshot.
Saved traces still work without Neovim and recover the display after a lost
connection. A lagging save of the currently streamed trace cannot replace its
in-progress tokens.

Use `f` to pause/resume following the bottom, `a` to toggle all content, `r` to
change reasoning styling on completed messages, and `q` to quit. The socket is a
read-only subscription; commands and user input still go through Neovim.

## Transport

Each Neovim process owns
`stdpath("state")/ask-openai/agents/live-<pid>.sock`, with permissions `0600`.
It is removed on normal exit. Unreachable sockets left by crashes are ignored and
retried; the viewer does not delete sockets belonging to other processes.
Slow readers are disconnected when their pending write queue exceeds 1 MiB,
rather than allowing an unbounded queue in Neovim. No history is serialized for
each token when no viewer is connected.

The protocol is newline-delimited JSON. Version 1 frames contain:

- `type: "snapshot"`, `version: 1`, and an increasing `sequence`.
- `trace_path`, `model_name`, `updated_at` (Unix seconds), and `status`.
- `replace_from`: the zero-based index where the previous message suffix is removed.
- `messages`: the replacement suffix. `_partial: true` selects literal rendering.

The first frame on each connection has `replace_from: 0`. Completion replaces the
partial message with the committed assistant message, so tokens and tool calls
are not duplicated. Tool results and newly added messages then extend the same
history. Multiple Neovim publishers are supported; the latest update selects the
trace being displayed. Older idle publishers do not take focus from newer work.

The shared state directory must have a sufficiently short path for Unix sockets
(typically 103 usable path bytes on macOS). A failed optional socket startup does
not prevent the agent from running or saving traces.

## Validation

```sh
.venv/bin/pytest -q tools/chat_viewer --override-ini 'python_files=*_tests.py'
nvim -i NONE --headless -c 'PlenaryBustedFile lua/ask-openai/agents/live_trace_stream.tests.lua'
```

The Python tests include a real headless Neovim publisher connected to the
Textual app, as well as fragmented socket reads, reconnects, suffix replacement,
partial JSON rendering, and disk/live reconciliation.
