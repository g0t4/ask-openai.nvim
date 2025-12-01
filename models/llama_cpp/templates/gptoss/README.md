## Links

```fish
#
# * openai's official jinja templates (20b/120b are the same):
# - 120b https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja
# - 20b https://huggingface.co/openai/gpt-oss-20b/raw/main/chat_template.jinja
#
# compare 120b and 20b => same
diff_two_commands 'curl -fsSL https://huggingface.co/openai/gpt-oss-20b/raw/main/chat_template.jinja' 'curl -fsSL https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja'
# copy external here:
wget https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja -O openai.jinja

# * unsloth's "fixes"
# https://huggingface.co/unsloth/gpt-oss-120b/raw/main/chat_template.jinja
wget https://huggingface.co/unsloth/gpt-oss-120b/raw/main/chat_template.jinja -O unsloth.jinja


```
