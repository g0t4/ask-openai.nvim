local M = {}

-- TODO for agentic... and all reasoning models, I need to split apart the <think> chunk when its done and display spearately, right?
--    make this a step before calling this method or a separate aspect so it can be reused in rewrites and other usage (i.e. agent tool eventually)
-- i.e. agentica's https://huggingface.co/agentica-org/DeepCoder-14B-Preview#usage-recommendations
M.DeepCoder = {

    build_completions_body = function(system_prompt, user_message)
        return {
        }
    end,

    build_chat_body = function(system_prompt, user_message)
        return {
            messages = {
                -- TODO if agentica recommends no system prompt.. would it make more sense to just use legacy completions for that use case oai_completions?
                { role = "user", content = system_prompt .. "\n" .. user_message },
            },
            -- Avoid adding a system prompt; all instructions should be contained within the user prompt.
            model = "agentica-org/DeepCoder-1.5B-Preview",
            -- TODO 14B-Preview quantized variant
            temperature = 0.6,
            top_p = 0.95,
            -- max_tokens set to at least 64000
            max_tokens = 64000,
            -- TODO can I just not set max_tokens too?
        }
    end

}

return M
