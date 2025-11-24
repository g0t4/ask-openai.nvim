#!/usr/bin/env fish

set base_url 'http://build21:8013'

# %% ** TEST prefill_assistant_message
#  can modify last "prefilled" assistant message!!
#      can provide literal prompt text!
#
#  see chat args parsing logic here:
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L727-L748
#  for /v1/chat/completions endpoint (obviously)
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L727-L763
#
#  FYI test w/ verbose-prompt on so you can see both INPUT and OUTPUT literal prompts:
#    __verbose.prompt (rendered jinja template + prefill additions)
#    __verbose.content (literal model response, w/o parsing for reasoning/tool_calls/etc)
#
#  IIUC can be disabled altogether (no last assistant message started at all) via CLI arg
#    but this is not what I want to test, I want to test using the prefill to inject thoughts (or w/e)
#    https://github.com/ggml-org/llama.cpp/blob/7d77f0732/common/arg.cpp#L2534
#

# * prefill (default on)
# normally a message ends with smth like this (this is gptoss):
#    <|start|>assistant
echo '{
  "messages": [
     { "role": "user", "content": "test" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq >prefill1.json
# btw here is raw prompt w/ system message cut out (...) for space:
#    "prompt": "<|start|>system<|message|>You are ChatGPT...<|end|><|start|>user<|message|>test<|end|><|start|>assistant",
#      NOTICE on the end is the standard prefill: <|start|>assistant
#
# response to the normal prefill (w/o last assistant message to inject more):
#    "content": "<|channel|>analysis<|message|>The user just says \"test\". Likely they want a response acknowledging test. Could be a simple reply: \"Test received. How can I help you?\" Probably respond.<|end|><|start|>assistant<|channel|>final<|message|>Test received! How can I assist you today?",
#      NOTICE model responds with thinking first (in thise case) => this was the setup with the defaul prefill
#

#
# * add_generation_prompt variable in template controls adding this default/initial prefill

# ***! prefill + assistant is last message w/ content string or array, injects values (i.e. to control thinking)
#  this allow you to prefill part of the assistant message! (i.e. disable thinking)

echo '{
  "messages": [
     { "role": "user", "content": "test" },
     { "role": "assistant", "content": "INJECTED RIGHT INTO PROMPT!!" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq >prefill2.json
# BTW what I INJECTED here breaks the typical flow and in this case the model responds with multiple messages, almost ignoring what I INJECTED
#  __verbose:
#     "prompt": "<|start|>system<|message|>You are ChatGPT...<|end|><|start|>user<|message|>test<|end|><|start|>assistantINJECTED RIGHT INTO PROMPT!!",
#        * note end as INJECTED literally added (not via template, this is a raw string appended)
#     "content": " \n\nIt looks ...<|end|><|start|>assistant<|channel|>analysis<|message|>The user just wrote \"test\". Likely they are testing. Should respond politely. Probably just echo or respond. As ChatGPT, respond \"Hello! How can I assist you today?\"<|end|><|start|>assistant<|channel|>final<|message|>Hello! How can I help you today?",
#       NOTE the bogus response => then <|end|> and right into a standard assist thinking message!
#       the model "recovered" in the next message
#        that's b/c I injected gibberish into the header (an invalid/unexpected role) results

# * use it to set part or all of thinking:
# in gptoss, add_generation_prompt injects this on end (and before any prefill):
# <|start|>assistant
# which allows gptoss to respond with analysis channel first, optionally tool calls on commentary channel, finally final channel w/ final message for the turn
#   btw I am not appending <|message|> after final b/c IIRC llama-cpp uses <|message|> as part of its partial processing for this prefilled message when then on the output side doesn't have a header
#
#   FTR can also pass array of content items instead of just one string
#
# here's the code where I found this:
#   https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L753-L762
#
echo '{
  "messages": [
     { "role": "user", "content": "test" },
     { "role": "assistant", "content": "<|channel|>analysis<|message|>no thoughts for you<|end|><|start|>assistant<|channel|>final" }
],
  "max_tokens": 80,
  "stream": false
}' | curl --fail-with-body -sSL --no-buffer "$base_url/v1/chat/completions" -d @- \
    | string replace --regex "^data: (\[DONE\])*" "" \
    # null entries for records w/o choices[0].delta.content
    | jq >prefill3.json
# BINGO! in this case I just get
#     "prompt": "<|start|>system<|message|>You are ChatGPT...<|end|><|start|>user<|message|>test<|end|><|start|>assistant<|channel|>analysis<|message|>no thoughts for you<|end|><|start|>assistant<|channel|>final",
#        NOTE my prefill additions force the model to produce a final response and NOTHING else
#        that is all that would be valid/expected after the final channel header
#        I leave <|message|> off b/c that should help the llama cpp parser find the first message contents (when the model generates that first)
#
#     "content": "<|message|>Test successful! 🎉 Let me know if there's anything you'd like to explore or discuss.",
#        NOTE.. NO THINKING! just the final message contents
#          FYI <|message|>...<|end|> maps to a given message's contents (not header)...
#            so model can't set role
#            can't really do anything without first finishing the message
#            and then the end of the finished message will stop generation (IIRC results in <|return|>
#
