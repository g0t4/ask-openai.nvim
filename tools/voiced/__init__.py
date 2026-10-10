"""Push-to-talk speech-to-text daemon for ask-openai voice control.

This is a proof of concept inspired by whisper.cpp's ``examples/stream``.
It captures mic audio while a push-to-talk key is held, streams it through
whisper.cpp for real-time transcription, and exposes a Unix domain socket
for IPC (newline-delimited JSON).
"""

