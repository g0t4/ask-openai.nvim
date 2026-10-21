local M = {}

-- Configuration keys select endpoints, params, and persisted reasoning settings.
--- @alias ConfigModel "gptoss" | "qwen" | "glm" | "gemma4" | "ds4" | "ds41" | "muse" | "nemo-lightning"
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GLM = "glm"
M.GEMMA4 = "gemma4"
M.DEEPSEEK = "ds4"
M.DEEPSEEK_41 = "ds41"
M.MUSE = "muse"
M.NEMO = "nemo-lightning"

M.CYCLE = {
    M.GPTOSS,
    M.QWEN,
    M.GEMMA4,
    M.GLM,
    M.DEEPSEEK,
    M.MUSE,
    M.NEMO,
}

--- @type ConfigModel
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


M.MODEL_AUTHOR_MAP = {
    [M.GPTOSS] = "gptoss120b<wes.mcclure+gptoss120b@gmail.com>",
    [M.QWEN] = "qwen3.6-35b-a3b<wes.mcclure+qwen3.6-35b-a3b@gmail.com>",
    [M.DEEPSEEK] = "deepseek-v4-flash<wes.mcclure+deepseek-v4-flash@gmail.com>",
    [M.DEEPSEEK_41] = "deepseek-v4.1-flash<wes.mcclure+deepseek-v4.1-flash@gmail.com>",
    [M.MUSE] = "muse-glimmer-30b-dspark<wes.mcclure+muse-glimmer-30b-dspark@gmail.com>",
}

local MODEL_PATTERNS = {
    -- FYI escape - => %- (easy to forget and will bork the pattern)
    --
    -- ALSO, order matters: more specific patterns first
    --
    -- ggml-org/Qwen3.6-35B-A3B-MTP-GGUF:Q8_0
    { pattern = "/Qwen3%.6.*%-MTP",     abbrev = "qwen3mtp" },
    -- ggml-org/Qwen3.6-35B-A3B-GGUF:Q8_0
    { pattern = "/Qwen3%.6",            abbrev = "qwen3" },
    -- g0t4/Qwen-AgentWorld-35B-A3B-GGUF:Q8_0
    { pattern = "/Qwen%-AgentWorld",    abbrev = "agentworld" },
    -- ggml-org/gpt-oss-120b-GGUF
    { pattern = "/gpt%-oss",            abbrev = "gptoss" },
    -- google/gemma-4-26B-A4B-it-qat-q4_0-gguf
    { pattern = "/gemma%-4",            abbrev = "gemma4" },
    -- ggml-org/GLM-4.7-Flash-GGUF:Q8_0
    { pattern = "/GLM%-4.7%-Flash",     abbrev = "glm" },
    -- ggml-org/DeepSeek-V4-Flash-0731-GGUF
    { pattern = "/DeepSeek%-V4-Flash", abbrev = "ds4" },
    -- vllm deepseek-v4.1-flash setup
    { pattern = "/DeepSeek%-V4.1-Flash", abbrev = "ds4.1" },
    { pattern = "/Muse%-Glimmer",       abbrev = "muse" },
    -- ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF:Q4_K_M
    { pattern = "/NVIDIA%-Nemotron",    abbrev = "nemo-lightning" },
}

--- Abbreviate an actual served model ID for display; never use this as a config key.
--- @param actual_model_name string|nil
--- @return string
function M.abbreviate_actual_model_name(actual_model_name)
    if not actual_model_name then
        return "MISSING_NAME"
    end

    for _, entry in ipairs(MODEL_PATTERNS) do
        if actual_model_name:match(entry.pattern) then
            return entry.abbrev
        end
    end

    return actual_model_name
end

return M
