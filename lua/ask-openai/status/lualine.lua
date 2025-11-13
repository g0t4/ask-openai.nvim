local local_share = require('ask-openai.config.local_share')
local human = require('devtools.humanize')

---@class lualine
---@field last_stats SSEStats|nil
local M = {}

-- TODO when switch model, I should reset the values
M.last_stats = nil

--- @param stats SSEStats?
function M.set_last_fim_stats(stats)
    M.last_stats = stats
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

    local function get_threshold_summary(icons)
        local level, _ = local_share.get_log_threshold()
        local icon = LEVEL_ICONS[level:lower()]
        if not icon then
            error("Unknown log threshold: " .. level)
        end
        table.insert(icons, icon)
    end

    return { {
        function()
            local icons = { '[' }

            get_threshold_summary(icons)

            if local_share.are_notify_stats_enabled() then
                table.insert(icons, '󰍨')
            end
            if local_share.is_rag_enabled() then
                table.insert(icons, '󰵉')
            end
            local fim_model = local_share.get_fim_model()
            if fim_model == "gptoss" then
                local level = local_share.get_reasoning_level()
                fim_model = fim_model .. "." .. level
            else
                local level = local_share.get_reasoning_level()
                fim_model = fim_model .. " " .. level
            end
            table.insert(icons, fim_model)
            if M.last_stats then
                if M.last_stats.prompt_tokens_per_second then
                    local text = "in@" .. human.format_num(M.last_stats.prompt_tokens_per_second, 0) .. "tps"
                    table.insert(icons, text)
                end
                if M.last_stats.predicted_tokens_per_second then
                    local text = "out@" .. human.format_num(M.last_stats.predicted_tokens_per_second, 0) .. "tps"
                    table.insert(icons, text)
                end
            end
            table.insert(icons, ']')

            return table.concat(icons, ' ')
        end,
        color = function()
            local fg_color = ''
            if not local_share.are_predictions_enabled() then
                fg_color = '#333333'
            end
            return { fg = fg_color }
        end,
    } }
end

return M
