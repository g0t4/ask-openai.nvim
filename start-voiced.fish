#!/usr/bin/env fish
# Start the voiced (push-to-talk + hands-free VAD) speech-to-text daemon.
# Hold the right Option key to talk, OR just speak hands-free (VAD auto-triggers).

cd (dirname (status --current-filename))
.venv/bin/python -m tools.voiced --handsfree $argv
