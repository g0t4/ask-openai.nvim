
## Works/observations:
- auto switch think vs non-think
  - i.e. FIM requests seem to always use non-think (direct)
- AskRewrite is working well

## Fixes in my code:
- blow up when I pass think content back to it in AskQuestion/AskToolUse
  - triggers a failure in the jinja template that builds the actual prompt on the llama-server side
  - this is on my first follow up after a think response
  - I am not sure I ever designed AskQuestion to be able to handle thinking responses, to not send back the think tags

## FIM

- I DID NOTHING TO GET FIM TO WORK! KEEP THAT IN MIND, the PROMPT IS FOR QWEN3-CODER

- FIM lua code:
  - works fine in `calc.lua`
  - not doing the basics for my new tool router.lua module!?
- other issues:
  - sometimes does well with predicting end of partial line
  - othertimes it falls apart
- other languages
  - I got reasonable response in systemd service files
  - markdown works
  - TODO other languages?
- find root cause and address
  - I need to find any official docs on how to use FIM too
  - i.e. should I be using chat completions for FIM? and if so, if I want repo-level FIM with other files do I need those in separarte chat messages?
  - could be training data? but I have a hard time believing they wouldn't have at least the same lua code everyone else has?

## Tool use:
- tool use will require XML parsing which I could easily add myself instead of having server do it
- it seems capable at tool calling but I need to see multi-turn and other real scenarios after I parse the XML tool calls



