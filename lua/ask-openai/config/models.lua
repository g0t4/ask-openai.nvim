local M = {}

--- @alias ModelName "gptoss" | "qwen" | "glm" | "gemma4" | "deepseek"
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GLM = "glm"
M.GEMMA4 = "gemma4"
M.DEEPSEEK = "deepseek"

M.CYCLE = {
    M.GPTOSS,
    M.QWEN,
    M.GEMMA4,
    M.GLM,
    M.DEEPSEEK,
}

--- @type ModelName
M.DEFAULT_MODEL = M.GPTOSS

--- @type string
M.THINKING_ON = "on"
M.THINKING_OFF = "off"

--- @enum GptOssReasoningLevel
M.GptOssReasoningLevel = {
    OFF = "off",
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high"
}

return M
