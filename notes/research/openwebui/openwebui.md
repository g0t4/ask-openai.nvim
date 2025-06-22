## notes about Open WebUI and it's tool use

### observations

- For all models, it is building a custom tool format (json based), and...
  - openhands LM (qwen2.5-coder finetune) does really good with it
  - qwen2.5-coder also does well with this format
  - qwen3 sometimes does ok with it, but a lot of failures too
  - Multiple round trips per user prompt
    - Another factor, openwebui prompts the model separately for a tool use (explicitly asks for tools - or empty list if don't want tools... so it forces model to pick one/some/none)
      - it provides user's prompt too, but in a diff way... the focus seems to be on tool use (structures the prompt to start out emphasizing tool use only, not user prompt... which is attached as almost a footnote)
    - Then, it evals tool calls and returns results ALONG with user prompt
      - almost as if the user had included a relevant tool call cuz the previous prompt is not in the thread now... just the tool call and result (AFAICT, I should double check what it does with thread after tool call completes)
- Using builtin templates in qwen models has done seemingly the opposite in my testing of AskToolUse
  - qwen3 ROCKS with this format
  - qwen2.5 IS TERRIBLE with its builtin format, keeps generating invalid XML tags around its tool calls
  - My AskToolUse simply prompts model w/ tools loaded and the user prompt in one round trip
    - if the model makes a tool call request, I do that and return result...
    - then it can respond to users original question...
    - I wonder if, in the event of a tool call, should I drop the previous message and make it look like the tool call came before the user's question?
      - right now, the models seem to do fine with answering the orig question (in the positon before the tool call.. and maybe that is the way it should be).
      - TODO what I should figure out is what they trained any given model to do? it really would depend on that for optimal tool use efficacy...
        then again, maybe not... as Open WebUI does well with its generic json based format! which json most models are well versed with too!

