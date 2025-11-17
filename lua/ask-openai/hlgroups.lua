local HLGroups = {}

-- * Roles
HLGroups.ASSISTANT = "AskAssistantRole"
HLGroups.USER = "AskUserRole"
HLGroups.SYSTEM_PROMPT = "AskSystemRole"
vim.api.nvim_set_hl(0, HLGroups.ASSISTANT, { fg = "#5A6FFF", italic = true, bold = true })
vim.api.nvim_set_hl(0, HLGroups.USER, { fg = "#A07CFF", italic = true, bold = true })
vim.api.nvim_set_hl(0, HLGroups.SYSTEM_PROMPT, { fg = "#D9C27A", italic = true, bold = true })

-- * Tools
HLGroups.TOOL_SUCCESS = "AskToolSuccess"
HLGroups.TOOL_FAILED = "AskToolFailed"
vim.api.nvim_set_hl(0, HLGroups.TOOL_SUCCESS, { fg = "#92E2AC", bg = "NONE" })
vim.api.nvim_set_hl(0, HLGroups.TOOL_FAILED, { fg = "#e06c75", bg = "NONE", bold = true })

-- * CHAT / :AskQuestion
HLGroups.CHAT_REASONING = "AskChatReasoning"
HLGroups.EXPLAIN_ERROR = "AskExplainError"
vim.api.nvim_set_hl(0, HLGroups.CHAT_REASONING, { fg = "#808080", italic = true })
-- TODO rewrite with nvim_set_hl
vim.api.nvim_command("highlight default " .. HLGroups.EXPLAIN_ERROR .. " guibg=#ff7777 guifg=#000000 ctermbg=red ctermfg=black")

-- * :AskRewrite
HLGroups.ASK_REWRITE = "AskRewrite"
vim.api.nvim_command("highlight default " .. HLGroups.ASK_REWRITE .. " guifg=#ccffcc ctermfg=green")

-- * PREDICTIONS
HLGroups.PREDICTION_TEXT = "AskPrediction"
vim.api.nvim_set_hl(0, HLGroups.PREDICTION_TEXT, { italic = true, fg = "#dddddd" })

--- * STATS
HLGroups.STATS_PROMPT = "AskStatsPrompt"
HLGroups.STATS_PREDICTED = "AskStatsPredicted"
HLGroups.STATS_CACHED = "AskStatsCached"
vim.api.nvim_set_hl(0, HLGroups.STATS_PROMPT, {
    fg = "#FF1493",
    bg = "NONE",
})
vim.api.nvim_set_hl(0, HLGroups.STATS_PREDICTED, {
    fg = "#FFFF00",
    bg = "NONE",
})
vim.api.nvim_set_hl(0, HLGroups.STATS_CACHED, {
    fg = "#2EBE10",
    bg = "none",
})

-- * RAG
HLGroups.RAG_HIGHLIGHT_LINES = "AskRagHighlightLines"
HLGroups.RAG_CHUNK_TYPE_ICON_LINE_RANGE = "Normal"
HLGroups.RAG_CHUNK_TYPE_ICON_TREESITTER = "AskRagChunkTypeTreesitter"
HLGroups.RAG_CHUNK_TYPE_ICON_UNCOVERED_CODE = "AskRagChunkTypeUncoveredCode"
vim.api.nvim_set_hl(0, HLGroups.RAG_HIGHLIGHT_LINES, { bg = "#414858" })
vim.api.nvim_set_hl(0, HLGroups.RAG_CHUNK_TYPE_ICON_TREESITTER, { fg = "#b0d5a6" })
vim.api.nvim_set_hl(0, HLGroups.RAG_CHUNK_TYPE_ICON_UNCOVERED_CODE, { fg = "#e24040" })

return HLGroups
