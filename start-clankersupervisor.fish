#!/usr/bin/env fish
# Start the clankersupervisor daemon, which manages voiced and clankerd.

cd (dirname (status --current-filename))
.venv/bin/python -m tools.clankersupervisor $argv

