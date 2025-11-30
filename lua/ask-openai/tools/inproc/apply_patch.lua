---@type InprocessTool
---@diagnostic disable-next-line: missing-fields
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

---@param parsed_args table
---@param callback ToolCallDoneCallback
function M.call(parsed_args, callback)
    local patch = parsed_args.patch
    -- cat ~/repos/github/g0t4/gpt-oss/gpt_oss/tools/example-add.patch | ~/repos/github/g0t4/gpt-oss/.venv/bin/python3 ~/repos/github/g0t4/gpt-oss/gpt_oss/tools/apply_patch.py
    local python = vim.fn.expand("~/repos/github/g0t4/gpt-oss/.venv/bin/python3")
    local apply_patch_py = vim.fn.expand("~/repos/github/g0t4/gpt-oss/gpt_oss/tools/apply_patch.py")
    -- local result = vim.fn.systemlist({ python, apply_patch_py }, patch)
    local result = vim.fn.system({ python, apply_patch_py }, patch)
    -- callback(result[1] or "")
end

-- BTW it is NOT possible w/ the current jinja template to create a tool that takes a single string arg! YIKES
--  and that's a BIG deal b/c otherwise it has to wrap it in JSON... and it can do that but if it wasn't fine tuned on that, it's gonna be less reliable
--   especially when modifying a file and needing to escape chars like " and ' etc
--   why did OpenAI release a jinja template that doesn't even support using their apply_patch tool?!?!

-- TODO any issues having two Tools sections in developer message (if I pass some tools via body.tools?)
local developer_message_apply_patch_tool_definition_only = [[
# Tools

## functions

namespace functions {

// Patch a file
type apply_patch = (_: string) => any;

} // namespace functions<|end|>
]]

-- FYI I rendered the message from the gpt-oss repo's chat.py and get the following (as I suspected)...
--  so, I need to inject this into the developer message myself, shouldn't hurt to have functions twice
--  OR how about I just build the # Tools section and not even pass tools to the API!
local FYI_chat_py_dev_message = [[
<|start|>developer<|message|># Instructions

foo

# Tools

## functions

namespace functions {

// Patch a file
type apply_patch = (_: string) => any;

} // namespace functions<|end|>
]]

function manual_test()
    -- test call
    local patch = [[
*** Begin Patch
*** Add File: new_module.py
+def hello():
+    """Simple hello function."""
+    print("Hello, world!")
*** End Patch
]]
    M.call({
        patch = patch,
    }, function()
    end)
end

return M
