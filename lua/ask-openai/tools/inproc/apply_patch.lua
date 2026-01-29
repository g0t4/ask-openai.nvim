local plumbing = require("ask-openai.tools.plumbing")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

-- PRN try other MCP based tools from gptoss repo (python code runner, browser)...
--   use their system message descriptions but route them through MCP in here

local string_arg = {
    -- model generates JSON string for args
    type = "string",
}

local alternative_dict_args = {
    -- model generates dict w/ single patch arg...
    --  this might be good if model doesn't reliably generate JSON string
    --  I wish openai published some training examples to better understand formats to consider
    type = "object",
    properties = {
        patch = {
            description = "file changes in custom diff format",
            type = "string"
        }
    },
    required = { "patch" }
}

-- type = "object", properties={patch ={ description=""...}} -- FYI can set type = "object" and template will use a dict... I fixed template to support string arg only (like you get when you use opeani-harmony repo's tool config so I want to go with that)
--  and JSON is ok btw... b/c then generated code is escaped as a JSON string (or dict if you go type=object)
--  which means anything inside the string won't conflict with gptoss message format (which is also XML and so JSON is a wise choice for args and results)

---@type OpenAITool;
M.ToolDefinition = {

    -- FYI gpt-oss apply_patch definition example:
    --   https://github.com/g0t4/gpt-oss/blob/017c732/gpt_oss/chat.py#L111-L119

    ["function"] = {
        description = "Patch a file",
        name = "apply_patch",
        ---@diagnostic disable-next-line: missing-fields
        -- parameters = string_arg, -- a few examples of missing " on the end of json dict (even though I say string it makes dict with patch proeprty, often)... fux it all up... I should add some error recovery?
        parameters = alternative_dict_args
    },
    type = "function"
}

M.DevMessageInstructions = nil

function M.get_system_message_instructions()
    if M.DevMessageInstructions then
        return M.DevMessageInstructions
    end
    local files = require("ask-openai.helpers.files")

    M.DevMessageInstructions = files.text_for("lua/ask-openai/tools/inproc/apply_patch.md")
        .. "\n\n" .. files.text_for("lua/ask-openai/tools/inproc/apply_patch_extended.md")
        .. "\n\n" .. files.text_for("lua/ask-openai/tools/inproc/commits.md")
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

    -- * python variant in gptoss repo:
    -- cat ~/repos/github/g0t4/gpt-oss/gpt_oss/tools/example-add.patch | ~/repos/github/g0t4/gpt-oss/.venv/bin/python3 ~/repos/github/g0t4/gpt-oss/gpt_oss/tools/apply_patch.py
    local python = vim.fn.expand("~/repos/github/g0t4/gpt-oss/.venv/bin/python3")
    -- local apply_patch_py = vim.fn.expand("~/repos/github/g0t4/gpt-oss/gpt_oss/tools/apply_patch.py")
    local apply_patch_multi = vim.fn.expand("~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools/inproc/apply_patch_multi.py")

    -- local apply_patch_rs = vim.fn.expand("~/repos/github/openai/codex/codex-rs/target/release/apply_patch")
    -- local result = vim.fn.system({ apply_patch_rs }, patch)

    -- PRN use async and get callback?
    -- FYI do not differentiate STDOUT/STDERR unless you can prove it fixes a problem with model performance
    local result = vim.fn.system({ python, apply_patch_multi }, patch)
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
        -- keep EXIT_CODE/isError here for your glue code at least... i.e. apply_patch.py file is missing! or no venv, or deps, etc...
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

-- NOTES apply_patch.py
-- - w/o dev message => generated Delete Then Add to update a file and that only deletes it! apply_patch has a bug in delete/add same file...  WTF?!?
--    likely fix is to add dev message instructions to remind about UpdateFile... and might need to fix this bug if it comes up still
--      yikes how the F does this happen with an official tool?!  that was used to fine tune?!?!

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

    -- make sure it can execute via either string or dict:
    -- M.call({ patch = patch, }, log_it)
    -- M.call(patch, log_it)
end

manual_test()

return M
