
## Works/observations:
- auto switch think vs non-think
  - i.e. FIM requests seem to always use non-think (direct)
- AskRewrite is working well

## Fixes in my code:
- blow up when I pass think content back to it in AskQuestion/AskToolUse
  - triggers a failure in the jinja template that builds the actual prompt on the llama-server side
  - this is on my first follow up after a think response
  - I am not sure I ever designed AskQuestion to be able to handle thinking responses, to not send back the think tags
- sometimes FIM is not helpful... i.e. some lua code this AM
  - need to find root cause and address
  - I need to find any official docs on how to use FIM too
     - i.e. should I be using chat completions for FIM? and if so, if I want repo-level FIM with other files do I need those in separarte chat messages?

## Tool use:
- tool use will require XML parsing which I could easily add myself instead of having server do it
- it seems capable at tool calling but I need to see multi-turn and other real scenarios after I parse the XML tool calls



