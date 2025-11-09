local local_share = require('ask-openai.config.local_share')

local M = {}

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
