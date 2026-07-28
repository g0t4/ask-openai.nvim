local M = {}

--- @enum ModelName
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GLM = "glm"
M.GEMMA4 = "gemma4"

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
