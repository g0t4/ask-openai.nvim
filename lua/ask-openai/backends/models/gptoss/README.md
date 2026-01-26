## Claude Code features I want to port to my gptoss prompts/tooling

- Commit after changes (that work)
- When committing, don't add other unrelated changes (not biggest deal but nicety)... I might forget something small and not wanna back it out
    - also shows discipline to review the changes
- Emphasize verification step
    - i.e. automated tests
    - run web apps and capture output (browser automation tools?)


##
The best way to make sure I understand this model is to parse the harmony format myself.
For example, I just recently discovered that it supports CoT tool use. And that I need to keep
the thinking tokens until a `final` message is generated. Even across turns (tool calls).

Anyways, I want to build my own streaming parser and really grasp the possible interactions.

Then I am free to use mine or go back to using jinja templates w/ llama.cpp (llama-server)


