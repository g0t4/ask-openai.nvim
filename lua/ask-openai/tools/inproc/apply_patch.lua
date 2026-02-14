local plumbing = require("ask-openai.tools.plumbing")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

-- FYI gpt-oss apply_patch definition example:
--   https://github.com/g0t4/gpt-oss/blob/017c732/gpt_oss/chat.py#L111-L119
--   FYI I settled on using object type for args, even though I had some luck with string based args to just contain the patch file in a "JSON string"

---@type OpenAITool;
M.ToolDefinition = {
    ["function"] = {
        description = "Patch a file",
        name = "apply_patch",
        parameters = {
            type = "object",
            properties = {
                patch = {
                    description = "file changes in custom diff format",
                    type = "string"
                }
            },
            required = { "patch" }
        }
    },
    type = "function"
}

M.DevMessageInstructions = nil

function M.get_system_message_instructions()
    if M.DevMessageInstructions then
        return M.DevMessageInstructions
    end
    local files = require("ask-openai.helpers.files")

    M.DevMessageInstructions = files.read_text("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/inproc/apply_patch.md")
        .. "\n\n" .. files.read_text("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/inproc/apply_patch_extended.md")
    return M.DevMessageInstructions
end

---@param parsed_args string|table
---@param callback ToolCallDoneCallback
function M.call(parsed_args, callback)
    local patch
    if type(parsed_args) == "table" then
        patch = parsed_args.patch
    elseif type(parsed_args) == "string" then
        patch = parsed_args
    else
        callback(plumbing.create_tool_call_output_for_error_message("Invalid parsed_args: " .. vim.inspect(parsed_args)))
        return
    end

    -- Check for multiple Begin/End Patch markers
    local begin_count = select(2, patch:gsub("%*%*%* Begin Patch", ""))
    local end_count = select(2, patch:gsub("%*%*%* End Patch", ""))

    if begin_count > 1 or end_count > 1 then
        vim.notify(
            "Patch contains multiple '*** Begin Patch' or '*** End Patch' lines, stripping extras.",
            vim.log.levels.ERROR
        )
        log:error("Original patch:\n" .. patch, vim.log.levels.ERROR)
    end

    -- * python adapter supports multiple patch files in one request
    local python = vim.fn.expand("~/repos/github/g0t4/gpt-oss/.venv/bin/python3")
    local runner = vim.fn.expand("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/inproc/apply_patch_wrapper.py")

    -- PRN use async and get callback?
    -- FYI do not differentiate STDOUT/STDERR unless you can prove it fixes a problem with model performance
    local result = vim.fn.system({ python, runner }, patch)
    log:info("apply_patch - vim.v.shell_error", vim.v.shell_error)

    -- apply_patch tool behaviors:
    --   STDERR used for DiffError, and in this case it doesn't set non-zero exit code

    -- chat.py app reference implementation does this for apply_patch tool call:
    --   https://github.com/g0t4/gpt-oss/blob/017c732/gpt_oss/chat.py#L189-L221
    --
    --   OK so it doesn't show non-zero exit codes
    --   only returns one item... the STDOUT/ERR or if an error then it returns error message as if it were STDOUT/ERR
    --     does not label anything STDOUT/STDERR so I will mirror that
    --
    --     content=[TextContent(text=tool_output)]
    --     maps to =>  return {"type": "text", "text": self.text}

    local exit_code = vim.v.shell_error
    if exit_code ~= 0 then
        -- keep EXIT_CODE/isError here for your glue code at least... i.e. missing wrapper script
        callback(plumbing.create_tool_call_output_for_error({
            -- do not name first result.. could be STDOUT or STDERR!
            plumbing.text_content(result),
            plumbing.text_content(tostring(exit_code), "EXIT_CODE"),
        }))
        return
    end

    callback(plumbing.create_tool_call_output_for_success({
        -- do not send EXIT_CODE if zero, because:
        -- 1. chat.py app doesn't...
        -- 2. apply_patch on DiffError still returns RC=0 w/ error message in output text (instead of STDOUT/ERR)
        --    thus, showing zero might confuse the model => causing it to ignore the error message text!
        plumbing.text_content(result)
    }))
end

-- notes
-- - https://developers.openai.com/api/docs/guides/tools-apply-patch
--   - suggests output format, same info I already have

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

    function log_it(call_output)
        log:info("manual_test() result", vim.inspect(call_output))
    end

    -- can execute via either string or dict, right now my tool logic uses object param
    -- M.call({ patch = patch, }, log_it)
    -- M.call(patch, log_it)
end

manual_test()

return M
