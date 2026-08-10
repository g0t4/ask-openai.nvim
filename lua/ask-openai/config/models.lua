local M = {}

--- @alias ModelName "gptoss" | "qwen" | "glm" | "gemma4" | "deepseek" | "muse"
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GLM = "glm"
M.GEMMA4 = "gemma4"
M.DEEPSEEK = "deepseek"
M.MUSE = "muse"

M.CYCLE = {
    M.GPTOSS,
    M.QWEN,
    M.GEMMA4,
    M.GLM,
    M.DEEPSEEK,
    M.MUSE,
}

--- @type ModelName
M.DEFAULT_MODEL = M.GPTOSS

--- @type string
M.THINKING_ON = "on"
M.THINKING_OFF = "off"
--- @enum REASONING_ON_OFF
M.CYCLE_REASONING_ON_OFF = {
    M.THINKING_OFF,
    M.THINKING_ON,
}

--- @enum GPTOSS_REASONING_EFFORT
M.GPTOSS_REASONING_EFFORT = {
    OFF = M.THINKING_OFF,
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high"
}
M.CYCLE_GPTOSS_REASONING_EFFORT = {
    M.GPTOSS_REASONING_EFFORT.OFF,
    M.GPTOSS_REASONING_EFFORT.LOW,
    M.GPTOSS_REASONING_EFFORT.MEDIUM,
    M.GPTOSS_REASONING_EFFORT.HIGH,
}

M.DEEPSEEK_REASONING_EFFORT = {
    OFF = M.THINKING_OFF,
    LOW = "low", -- AFAICT this is the level used by default in jinja template packaged with llama.cpp
    HIGH = "high",
    MAX = "max",
    PSM = "PSM", -- native fim tokens, only applies to FIM (predictions)
    -- PRN add File vs Repo FIM?
}
---@enum DEEPSEEK_REASONING_EFFORT
M.CYCLE_DEEPSEEK_REASONING_EFFORT = {
    M.DEEPSEEK_REASONING_EFFORT.OFF,
    M.DEEPSEEK_REASONING_EFFORT.LOW,
    M.DEEPSEEK_REASONING_EFFORT.HIGH,
    M.DEEPSEEK_REASONING_EFFORT.MAX,
    M.DEEPSEEK_REASONING_EFFORT.PSM,
}

--- @enum MUSE_REASONING_EFFORT
M.MUSE_REASONING_EFFORT = {
    OFF = M.THINKING_OFF,
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high",
    XHIGH = "xhigh",
}
M.CYCLE_MUSE_REASONING_EFFORT = {
    M.MUSE_REASONING_EFFORT.OFF,
    M.MUSE_REASONING_EFFORT.LOW,
    M.MUSE_REASONING_EFFORT.MEDIUM,
    M.MUSE_REASONING_EFFORT.HIGH,
    M.MUSE_REASONING_EFFORT.XHIGH,
}

return M
