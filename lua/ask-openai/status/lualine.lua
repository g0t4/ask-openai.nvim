local local_share = require('ask-openai.config.local_share')

---@class lualine
---@field last_stats SSEStats|nil
local M = {}

-- TODO when switch model, I should reset the values
M.last_stats = nil

--- @param stats SSEStats?
function M.set_last_fim_stats(stats)
    M.last_stats = stats
end

function M.lualine()
    -- FYI this is an example, copy and modify it to your liking!
    -- reference: "󰼇" "󰼈"
    --  ''            󰨰   (test/debug)
    --  󰵉  󱐎  󰵕  search axis/arrow
    --     󰕡 (search vector)

    return {
        function()
            local icons = { '󰼇' }
            if local_share.are_verbose_logs_enabled() then
                table.insert(icons, '')
            end
            if local_share.are_notify_stats_enabled() then
                table.insert(icons, '󰍨')
            end
            if local_share.is_rag_enabled() then
                table.insert(icons, '󰵉')
            end
            table.insert(icons, local_share.get_fim_model())
            if M.last_stats then
                if M.last_stats.predicted_tokens_per_second then
                    table.insert(icons, tostring(M.last_stats.predicted_tokens_per_second))
                end
                if M.last_stats.prompt_tokens_per_second then
                    table.insert(icons, tostring(M.last_stats.prompt_tokens_per_second))
                end
            end
            return table.concat(icons, ' ')
        end,
        color = function()
            local fg_color = ''
            if not local_share.are_predictions_enabled() then
                fg_color = '#333333'
            end
            return { fg = fg_color }
        end,
    }
end

return M
