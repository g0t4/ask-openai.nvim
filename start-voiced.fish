#!/usr/bin/env fish
# Start the voiced (push-to-talk speech-to-text) daemon.
# Hold the fn key to talk; transcriptions stream to ask-openai clients.

cd (dirname (status --current-filename))
.venv/bin/python -m tools.voiced $argv

