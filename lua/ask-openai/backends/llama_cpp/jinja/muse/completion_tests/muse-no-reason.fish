#!/usr/bin/env fish


# FYI just defining a last assistant message is enough with eixsting muse glimmer jinja template to get "prefill" to control the assistant response to BLOCK THINKING!
#   btw add_generation_prompt is true by default (leave true works fine here)... if you want to change it, it is BODY level not chat_template_kwargs level

curl -X POST http://paxy:8016/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
       "messages": [
          { "role": "user", "content": "What time is it?" },
          { "role": "assistant", "reasoning_content": "<|eom|><|start|>assistant to=user<|message|>", "content": "" }
        ],
        "temperature": 1.0,
        "top_p": 1.0,
        "max_tokens": 300,
        "chat_template_kwargs": {
          "reasoning_strength": "low"
        }
      }' \
    | jq
    # '{ __verbose, choices }'

    # FYI in my testing
    #  `<|start|>assistant to=self<|message|>` is added if my last message is role=assistant w/ reasoning_content set (b/c jinja template detects this and fills as reasoning... on a prefill message)
    #  btw I can put in reasoning if I want (fixed reasoning text) or just leave empty at the start of the reasoning_content last assistant msg
    #  and then reasoning content cuts of reasoning and prefills into the final response
    #   `<|eom|><|start|>assistant to=user<|message|>`
    #   then we set empty content field, seems to work fine
    #
    # "content": " What time is it?\n\nWe need respond. No time access. Probably ask clarification. Could give current UTC? Cannot know exact. Provide guidance.\n\nWe should say I don't have real-time clock, but can tell you how to check. Maybe give approximate based on knowledge cutoff? No.\n\nRespond politely: I don't have access to real-time. Could approximate? Probably say I can't know.\n\nFollow policy.<|eom|><|start|>assistant to=user<|message|>I don't have access to a real-time clock, so I can't see the exact current time for you right now.\n\nIf you tell me your time zone, I can help you figure out what time it should be, or you can check it on your device:\n* **Phone / Computer:** Most devices show the time on the lock screen or menu bar\n* **Online:** time.google.com or worldclock.com will show local time\n\nWhat time zone are you in?<|eot|>",

              # { "role": "assistant", "content": "<|start|>assistant" }


# FYI confirmed add_generation_prompt is on the body, not chat_template_kwargs
#     https://github.com/ggml-org/llama.cpp/blob/030ebb558/tools/server/server-common.cpp#L1045

# ./muse-no-reason.fish
