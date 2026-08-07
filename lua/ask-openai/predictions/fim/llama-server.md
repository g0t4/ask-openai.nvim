```lua
-- * llama-server /completions endpoint
response_fields = {
    -- FYI this primarily limits what shows in the final SSE under .__verbose (when --verbose-prompt is enabled)
    --   FYI previously I didn't have "prompt" in the list, so it was eliminating that in .__verbose.prompt
    --   * TLDR be cautious with adding this back, it has led to confusion when I didn't realize it was limiting the fields for --verbose-prompt
    -- set fields so the rest are skipped, else the SSEs are HUGE, and last has entire prompt too
    "content", "timings", "truncated", "stop_type", "stopping_word",
    "generation_settings", "prompt" -- for last SSE to reflect inputs
},
-- these seem to be included regardless: "index","content","tokens","stop","id_slot","tokens_predicted","tokens_evaluated"

timings_per_token = false, -- default false, shows timings on every SSE, BTW doesn't seem to control tokens_predicted, tokens_evaluated per SSE
```
