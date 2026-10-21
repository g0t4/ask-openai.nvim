local models = require("ask-openai.config.models")
local local_share = require('ask-openai.config.local_share')
local perf = require("ask-openai.perf")
local human = require('devtools.humanize')
local llama_stats = require('ask-openai.backends.llama_cpp.stats')
local mcp_tools = require('ask-openai.tools.mcp')

---@class lualine
---@field last_fim_stats SSEStats|nil
local M = {}

-- TODO when switch model, I should reset the values
M.last_fim_stats = nil

---@param stats SSEStats?
function M.set_fim_last_sse(stats, sse)
    M.last_fim_stats = stats
    M.last_fim_sse = sse
end

local LEVEL_ICONS = {
    trace = "∙", -- or "…" / "⋯" / "·"
    debug = "",
    info  = "",
    warn  = "",
    error = "",
}

function M.lualine_components()
    -- FYI this is an example, copy and modify it to your liking!
    -- reference: "󰼇" "󰼈"
    --  ''            󰨰   (test/debug)
    --  󰵉  󱐎  󰵕  search axis/arrow
    --     󰕡 (search vector)

    local enabled_color = function()
        local fg_color = ''
        if not local_share.are_predictions_enabled() then
            fg_color = '#333333'
        end
        return { fg = fg_color }
    end

    -- * MCP indicator (separate component for per-segment coloring)
    --   Uses 5 dots to make the state more visible at a glance.
    --   Ready:     ●●●●● (green filled dots)
    --   Not ready: ○○○○○ (red hollow dots)
    local mcp_dot_color = function()
        local is_ready = mcp_tools.ready
        return { fg = is_ready and '#50fa7b' or '#ff5555' } -- green or red
    end

    local primary = {
        function()
            local icons = { '[' }

            -- * Show recent performance stats from most recently used frontend
            local recent_stats = perf.get_recent_stats()
            if recent_stats and recent_stats ~= "" then
                table.insert(icons, recent_stats)
            end

            if local_share.are_notify_stats_enabled() then
                table.insert(icons, '󰍨')
            end
            if local_share.is_rag_enabled() then
                table.insert(icons, '󰵉')
            end

            -- -- -- show last FIM model used ... do not query /v1/models in advance
            -- -- --  TODO how do I want to show this? should I only show full name if mismatch vs expected?
            -- local last_fim_model = nil
            -- if M.last_fim_sse and M.last_fim_sse.model then
            --     last_fim_model = M.last_fim_sse.model
            -- end
            -- if last_fim_model == "ggml-org/gpt-oss-120b-GGUF" then
            --     -- last_fim_model = "gptoss"
            -- end

            -- * FIM status
            local level = local_share.get_fim_reasoning_level():upper()
            local fim_status = "p/" .. local_share.get_fim_model() .. level:sub(1, 1)
            table.insert(icons, fim_status)

            -- * rewrite status
            -- btw gray out on rewrite level does not mean it is disabled, it will still work fine even when FIM is disabled
            local rewrite_model = local_share.get_rewrite_model()
            local level = local_share.get_rewrite_reasoning_level():upper()
            local rewrite_status = "r/" .. rewrite_model .. level:sub(1, 1)
            table.insert(icons, rewrite_status)

            -- * agents status
            local agents_model = local_share.get_agents_model()
            local level = local_share.get_agents_reasoning_level():upper()
            local agents_status = "a/" .. agents_model .. level:sub(1, 1)
            table.insert(icons, agents_status)

            if M.last_fim_stats then
                if M.last_fim_stats.prompt_tokens_per_second then
                    local text = "in@" .. human.format_num(M.last_fim_stats.prompt_tokens_per_second, 0) .. "tok/s"
                    table.insert(icons, text)
                end
                if M.last_fim_stats.predicted_tokens_per_second then
                    local text = "out@" .. human.format_num(M.last_fim_stats.predicted_tokens_per_second, 0) .. "tok/s"
                    table.insert(icons, text)
                end
            end
            table.insert(icons, ']')

            -- * aggregate stats (across requests)
            local totals = llama_stats.totals

            if totals.prompt_tokens ~= 0 then
                -- FYI right now only predictions updates the counters so call it ptot until others use this
                local summary = string.format("ptot: %sin %sout",
                    human.count(totals.prompt_tokens),
                    human.count(totals.predicted_tokens)
                )
                table.insert(icons, summary)
            end

            return table.concat(icons, ' ')
        end,
        color = enabled_color,
        separator = nil,
        padding = 1 -- left/right padding (# chars)
    }

    local mcp_component = {
        function()
            local is_ready = mcp_tools.ready
            local dot_char = is_ready and '●' or '●●●●●●●●●●●●●●●●●●●●●●●●●●●'
            return dot_char
        end,
        color = mcp_dot_color,
        separator = { left = ' ', right = '' },
        padding = 0
    }

    -- TODO revisit multi component styling (i.e. color, padding, etc)
    return {
        primary,
        mcp_component,
    }
end

return M
