local M = {}

---@type OpenAITool
M.ToolDefinition = {
    -- tool definition based on gpt-oss repo:
    --   https://github.com/g0t4/gpt-oss/blob/2cb651c/gpt_oss/chat.py#L101-L123
    --     UGH... this looks like it wouldn't render with gpt-oss's template... unless the server does something to map parameters to parameters.properties (but then there's no name?)
    --     OR, does the client in chat.py change things? It doesn't seem so b/c I see BaseModel (pydantic) which suggests these are verbatim passed to backend server
    --      it is possible that OpenAI's server does some things to change what gets mapped in?
    --      or is this chat app intended for say ollama backend? or llama-cpp... do either of these transform the single parameter case to work with gptoss template?
    --        I guess what would it matter? it would have to be a named property for that template (jinja) to render it... so I can just set name myself
    -- parameters={
    --     "type": "string",
    --     "description": "Formatted patch code",
    --     "default": "*** Begin Patch\n*** End Patch\n",
    -- }
    --


    -- FYI confirmed tools structure matches template expectations:
    --   https://github.com/ggml-org/llama.cpp/blob/10e978015/models/templates/openai-gpt-oss-120b.jinja#L108-L149
    --   notably expects tool.function for definition L112
    ["function"] = {
        description = "Patch a file",
        name = "apply_patch",
        parameters = {
            type = "object",
            properties = {
                -- FYI must have parameters.properties to render in gptoss120b template
                --   so create one named property "patch"
                -- TODO how about add my own explanation to developer message and not send apply_patch in tools? AFAICT this is just an update to the developer message on the server side?
                --   TODO can you run the chat.py app and see what it is sending for this structure!
                --   it almost looks like it won't render any properties in the jinja template for it!
                patch = {
                    -- TODO multiple patch files? the apply_patch.md file suggests can have multiple
                    --    TODO is it all in one string value and I split them?
                    --       btw apply_patch.py right now only takes one, but I could easily split on first line of each
                    --    TODO or, should I accept an array of strings?
                    --    TODO can I get any hint about what the tool looked like in training?
                    type = "string",
                    description = "Formatted patch code",
                    default = "*** Begin Patch\n*** End Patch\n",
                }
            },
            required = { "patch" }
        }
    },
    type = "function"
}

return M
