#!/usr/bin/env fish
# Start the clankerd (primary brain) daemon.
# It listens to voiced transcriptions and takes action via LangChain + MCP tools.

cd (dirname (status --current-filename))
.venv/bin/python -m tools.clankerd $argv
