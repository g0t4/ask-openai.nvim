local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
local BufferController = require("ask-openai.agents.viewer.buffers")
local HLGroups = require("ask-openai.hlgroups")
local FloatWindow = require("ask-openai.helpers.float_window")

--- Unicode spinner frames for smooth animation.
local SPINNER_FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

---@class AgentWindow : FloatWindow
---@field buffer_number number
---@field buffer BufferController
---@field win_id number
---@field _model_name string
---@field _spinner_handle? table -- vim.loop.timer_t handle
---@field _spinner_idx number
---@field _base_title string
---@field _agent_is_running boolean
local AgentWindow = {}
local class_mt = { __index = FloatWindow } -- inherit FloatWindow behavior too
setmetatable(AgentWindow, class_mt)

---@param model_name string
function AgentWindow:new()
    ---@type FloatWindowOptions
    local opts = {
        width_ratio = 0.6,
        height_ratio = 0.8,
        filetype = "markdown",
        buffer_name = 'AskAgent',
    }

    local instance_mt = { __index = self } -- FYI self is likely AgentWindow here

    local instance = setmetatable(FloatWindow:new(opts), instance_mt)
    instance._model_name = nil

    instance.buffer = BufferController:new(instance.buffer_number)

    -- * buffer local keymaps
    vim.keymap.set('n', '<leader>c', function() instance:clear() end,
        { buffer = instance.buffer_number, desc = "clear the chat window, and eventually the message history" })

    -- Cycle the chat window width with a normal‑mode "w" press.
    vim.keymap.set('n', '<leader>aw', function() instance:cycle_width() end,
        { buffer = instance.buffer_number, desc = "cycle chat window width" })

    -- Cycle the chat window height with a normal‑mode "h" press.
    vim.keymap.set('n', '<leader>ah', function() instance:cycle_height() end,
        { buffer = instance.buffer_number, desc = "cycle chat window height" })

    -- manually trigger LSP attach, b/c scratch buffers are normally not auto attached
    local client = vim.lsp.get_clients({ name = "ask_language_server" })[1]
    if client then vim.lsp.buf_attach_client(instance.buffer_number, client.id) end

    -- * folding options
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.MyAgentWindowFolding()"
    vim.opt_local.foldenable = true
    vim.opt_local.foldlevel = 0 -- CLOSE all folds with higher number, thus 0 == ALL (equiv to zM => foldenable + foldlevel=0)

    -- assistants tend to write long paragraphs w/o \n line breaks, definitely need to wrap!
    vim.opt_local.wrap = true

    return instance
end

function AgentWindow:update_model_name(model_name)
    self._model_name = model_name
    self:rebuild_title()
end

function AgentWindow:rebuild_title()
    -- * rebuild title
    local parts = {}
    if self._spinner_frame then
        table.insert(parts, self._spinner_frame)
    end
    if self._model_name then
        table.insert(parts, self._model_name)
    end
    if self._base_title then
        table.insert(parts, self._base_title)
    end
    local title = table.concat(parts, " - ")
    self:set_title(title)

    -- * rebuild footer (currently one part only)
    local footer_parts = {}
    if self._spinner_frame then
        table.insert(footer_parts, self._spinner_frame)
    end
    if self._footer then
        table.insert(footer_parts, self._footer)
    end
    local footer = table.concat(footer_parts, " - ")
    self:set_footer(footer)
end

---@param base_title? string -- optional static text to display alongside the spinner
function AgentWindow:ensure_spinner_running(base_title)
    if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
        return
    end

    if base_title then
        self._base_title = base_title
    end

    if not self._spinner_handle then
        self._spinner_idx = 1

        -- * timer fires every 100ms for smooth animation
        local handle = vim.loop.new_timer()
        handle:start(0, 100, function()
            if not self._agent_is_running then
                -- stop when agent is done
                -- or never start if agent isn't running
                self:stop_spinner()
                return
            end

            -- Must schedule into normal event loop since nvim_win_is_valid can't be called in fast events
            vim.schedule(function()
                if not vim.api.nvim_win_is_valid(self.win_id) then
                    handle:stop()
                    return
                end

                self._spinner_idx = (self._spinner_idx % #SPINNER_FRAMES) + 1
                self._spinner_frame = SPINNER_FRAMES[self._spinner_idx]

                self:rebuild_title()
            end)
        end)

        self._spinner_handle = handle
    end
end

--- Stop the spinner animation and optionally set a final static title.
---@param final_title? string -- optional title to set after stopping the spinner
function AgentWindow:stop_spinner(final_title)
    if self._spinner_handle then
        self._spinner_handle:stop()
        self._spinner_handle:close()
        self._spinner_handle = nil
    end

    self._spinner_frame = nil
    self._base_title = final_title or self._base_title
    self:mark_agent_running(false) -- FYI consider cart/horse... mark agent running might be how I want to stop the spinner, instead of stop spinner => mark agent running (false)...
    self:rebuild_title()
end

---@param width_ratio number -- new width ratio (0 to 1)
function AgentWindow:resize_width_ratio(width_ratio)
    self.opts.width_ratio = width_ratio

    -- clamp the ratio between 0 and 1
    self.opts.width_ratio = math.max(0, math.min(self.opts.width_ratio, 1))

    -- apply the new size by recreating the window
    self:close()
    self:open()
end

---@param height_ratio number -- new height ratio (0 to 1)
function AgentWindow:resize_height_ratio(height_ratio)
    self.opts.height_ratio = height_ratio

    -- clamp the ratio between 0 and 1
    self.opts.height_ratio = math.max(0, math.min(self.opts.height_ratio, 1))

    -- apply the new size by recreating the window
    self:close()
    self:open()
end

--- Cycle the width ratio through a predefined set of values.
--- The sequence is 0.5 → 0.6 → 0.8 → 1.0 → back to 0.5.
function AgentWindow:cycle_width()
    -- Increment width by 0.1, wrapping back to 0.5 after 1.0.
    local step = 0.1
    local min_ratio = 0.5
    local max_ratio = 1.0
    local current = self.opts.width_ratio
    local next_ratio = current + step
    if next_ratio > max_ratio + 1e-6 then
        next_ratio = min_ratio
    else
        -- round to one decimal place to avoid floating‑point drift
        next_ratio = math.floor(next_ratio * 10 + 0.5) / 10
    end
    self:resize_width_ratio(next_ratio)
end

--- Cycle the height ratio by 0.1 steps, wrapping from a minimum (0.1 less than the current height) back to 1.0.
function AgentWindow:cycle_height()
    local step = 0.1
    local max_ratio = 1.0
    local min_ratio = 0.6
    local current = self.opts.height_ratio
    local next_ratio = current + step
    if next_ratio > max_ratio + 1e-6 then
        next_ratio = min_ratio
    else
        next_ratio = math.floor(next_ratio * 10 + 0.5) / 10
    end
    self:resize_height_ratio(next_ratio)
end

---@type ExplainError
function AgentWindow:explain_error(text)
    local lines = LinesBuilder:new()
    lines:create_marks_namespace()
    lines:append_styled_text(text, HLGroups.EXPLAIN_ERROR)
    lines:append_blank_line()
    self:append_styled_lines(lines)
end

---@param lines LinesBuilder
function AgentWindow:append_styled_lines(lines)
    self.buffer:append_styled_lines(lines)
end

--- clear the window contents only (not message history)
function AgentWindow:clear()
    self.buffer:clear()
end

function AgentWindow:close()
    -- stop the spinner animation before closing
    self:stop_spinner()
    -- TODO still issues around closing window and re-open it... not showing the title + spinner until I close and reopen again
    --   IOTW open window by running sleep 30s prompt... then F8 close.... esc ... <leader>ao ... (no spinner in title, no title actually)... then F8 close again ... <leader>ao .. this time title shows?!?!
    vim.api.nvim_win_close(0, true)
end

function AgentWindow:open()
    FloatWindow.open(self)
    self:ensure_spinner_running() -- it will stop itself
    return self
end

function AgentWindow:mark_agent_running(value)
    self._agent_is_running = value
end

return AgentWindow
