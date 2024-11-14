local M = {}

function M.setup(opts)
    require("ask-openai.cmd-suggest")

    require("ask-openai.config").set_user_opts(opts)

    -- TODO modify this to use github copilot subscription/api using chat model and see how it performs vs openai gpt4o (FYI windows terminal chat w/ copilot was clearly inferior vs gpt4o but ... win term chat might have been using gpt3.5 or smth else, just FYI"

    local cmd_suggestions = require("ask-openai.cmd-suggest")
    cmd_suggestions.setup_cmd_suggestions()

    local hints = require("ask-openai.hints")
    hints.setup_hints()
end

return M
