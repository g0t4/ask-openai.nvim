#!/usr/bin/env fish

export OLLAMA_HOST='ollama:11434'

ollama create fim_qwen:7b-instruct-q8_0 \
    -f 7b-instruct-q8_0.Modelfile

