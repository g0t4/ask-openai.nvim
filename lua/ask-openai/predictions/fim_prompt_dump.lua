local llama_server_client = require("ask-openai.backends.llama_cpp.llama_server_client")
local FloatWindow = require("ask-openai.helpers.float_window")
local combined = require("devtools.diff.combined")
local should = require("devtools.tests.should")
local messages = require("devtools.messages")

local M = {}

---@param fim_request CurlRequest
function M.dump_rendered_prompt_only(fim_request)
    -- PRN? move this out into its own module, composed with new open_float
    local response = llama_server_client.apply_template(fim_request.base_url, fim_request.body)
    local prompt = response.body.prompt
    local lines = vim.split(prompt, '\n')

    -- * hack to diff vs last prompt to point out changes easier
    -- show diff vs last prompt (i.e. toggle FIM reasoning level, or more cursor to new spot to FIM)
    if M.__last_prompt then
        -- deps:
        -- diff:
        local diff = combined.combined_word_diff(prompt, M.__last_prompt)
        local inspected = should.inspect_diff(diff)
        -- show it:
        messages.append(inspected)
        messages.ensure_open()
    end

    ---@type FloatWindowOptions

    local buf, win = FloatWindow:new(
        { width_ratio = 0.8, height_ratio = 0.8, filetype = "harmony" },
        lines
    )
    -- PRN? setup harmony grammar for filetype + coloring with treesitter?
    -- PRN? or use LinesBuilder for lines w/ extmarks using LinesBuilder (not hard to do either, and would get me to setup a simple parser!)

    M.__last_prompt = prompt -- track so I can diff two versions
end

return M
