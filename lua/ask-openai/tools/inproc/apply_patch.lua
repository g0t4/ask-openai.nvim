---@type InprocessTool
---@diagnostic disable-next-line: missing-fields
local M = {}

-- TODO extra instructions for system message (goes into developer message for gptoss)
M.SystemMessageExplanation = {

}

M.ToolDefinition = {
    -- FYI confirmed jinja expects tool.function: https://github.com/ggml-org/llama.cpp/blob/10e978015/models/templates/openai-gpt-oss-120b.jinja#L108-L149
    ["function"] = {
        description = "Patch a file",
        name = "apply_patch",
        ---@diagnostic disable-next-line: missing-fields
        parameters = {
            type = "string",
            -- FYI I had to patch the jinja template to support string only arg (otherwise it forces to use dict which means needless JSON wrapper)
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
--   FYI I rendered this via: https://github.com/g0t4/gpt-oss/blob/017c732/gpt_oss/chat.py#L129-L133
--     also https://github.com/g0t4/gpt-oss/blob/2cb651c/gpt_oss/chat.py#L101-L123
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
