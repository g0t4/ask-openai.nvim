## * llama-server (llama cpp)

<|channel|>analysis<|message|>User wrote "test". Likely just a test message. They might want ChatGPT to respond? We should respond politely. Maybe just say "Hello! How can I help?"<|start|>assistant<|channel|>final<|message|>Hello! 👋 How can I assist you today?

this assumes that in the original message you added <|start|>assistant
- and thus it continues right into the <|channel|> as start of response

here is what the COMPLETE output would look like:
  https://cookbook.openai.com/articles/openai-harmony#example-output

However, <|end|> and <|return|> are both stripped by llama-server
- no idea why touch it at all if you are leaving most of it?!


TLDR:
- treat this sequence as the "<think>" tag
  <|channel|>analysis<|message|>
- treat this sequence as the "</think>" tag
  <|start|>assistant<|channel|>final<|message|>

