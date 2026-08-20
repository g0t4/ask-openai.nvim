local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
local BufferController = require("ask-openai.agents.viewer.buffers")
local HLGroups = require("ask-openai.hlgroups")
local FloatWindow = require("ask-openai.helpers.float_window")
local layout = require("ask-openai.agents.viewer.layout")

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

--- Fill the usable screen above the user input box (full width, no centering).
--- The input box reserves `layout.INPUT_HEIGHT` content rows at the bottom of the
--- usable float area (`layout.editor_height()`, which excludes the command line).
--- Because float borders are drawn OUTSIDE the config area, we subtract an extra
--- row so this window's bottom border lands on the same row as the input box's
--- top border (a single shared border row, no content overlap).
--- NOTE: defined with DOT (not colon) to match FloatWindow.window_config's signature.
---@param opts FloatWindowOptions
---@return vim.api.keyset.win_config
function AgentWindow.window_config(opts)
    -- content height. The invisible border still reserves the top/bottom rows so the
    -- spinner title + footer keep rendering, but no box is drawn. We extend one row
    -- taller than the old shared-border math so the chat's last content line lands on
    -- the input box's (invisible) top border row - closing the one-line gap that
    -- appeared once both borders became invisible. The two windows sit flush and are
    -- told apart purely by background color (chat blends into the editor bg).
    local win_height = math.max(1, layout.editor_height() - layout.INPUT_HEIGHT)
    local win_width = vim.o.columns
    return {
        row = 0,
        col = 0,
        width = win_width,
        height = win_height,
        relative = "editor",
        style = "minimal",
        -- empty border cells => no visible box, but the title/footer rows remain
        border = { "", "", "", "", "", "", "", "" },
        -- blend the chat viewer into the editor background (no tinted pane)
        winhighlight = "NormalFloat:Normal",
    }
end

---@param model_name string
function AgentWindow:new()
    ---@type FloatWindowOptions
    local opts = {
        filetype = "markdown",
        buffer_name = 'AskAgent',
    }

    -- NOTE: pass `AgentWindow` as the receiver so the instance inherits from this class
    -- from the start (giving us our top-filling window_config) on the initial open,
    -- rather than opening centered via FloatWindow and re-parenting after.
    local instance = FloatWindow.new(AgentWindow, opts)
    instance._model_name = nil

    instance.buffer = BufferController:new(instance.buffer_number)
    instance.buffer.win_id = instance.win_id

    -- * buffer local keymaps
    vim.keymap.set('n', '<leader>c', function() instance:clear() end,
        { buffer = instance.buffer_number, desc = "clear the chat window, and eventually the message history" })

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
    -- * track the owning window on the buffer so cursor/scroll ops work even when
    --   another window (e.g. the user input box) has focus
    if self.buffer then
        self.buffer.win_id = self.win_id
    end
    self:ensure_spinner_running() -- it will stop itself
    return self
end

function AgentWindow:mark_agent_running(value)
    self._agent_is_running = value
end

return AgentWindow
