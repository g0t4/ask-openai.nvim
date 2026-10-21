local M = {}
local client = require("ask-openai.backends.llama_cpp.llama_server_client")
local models = require("ask-openai.config.models")
---@class EndpointModelInfo
---@field base_url? string
---@field status "pending"|"ready"|"fetch_failed"|"no_endpoint"
---@field backend string
---@field actual_model_name? string @Verbatim model ID returned by the endpoint
---@field actual_model_abbreviation? string @Display label; never a routing or params key
---@field actual_model_info? ModelInfo
local snapshots, generations, waiting = {}, {}, {}

-- No shell, waits, timers, or synchronous HTTP on Neovim's event loop.
local function get_json(url, callback)
    vim.system({ "curl", "-sS", "--connect-timeout", "1", "--max-time", "3",
        "-w", "\n%{http_code}", url }, { text = true }, function(result)
        vim.schedule(function()
            local body, status = (result.stdout or ""):match("^(.*)\n(%d+)%s*$")
            local ok, decoded = pcall(vim.json.decode, body or "")
            callback(result.code == 0 and tonumber(status) == 200 and ok and decoded or nil)
        end)
    end)
end

local function detect(body)
    for _, model in ipairs(type(body.data) == "table" and body.data or {}) do
        if model.owned_by == "llamacpp" then return "llama-server" end
        if model.owned_by == "vllm" then return "vllm" end
    end
end

function M.get(base_url)
    if type(base_url) ~= "string" or base_url == "" then
        return { status = "no_endpoint", backend = "unknown" }
    end
    return snapshots[base_url] or { status = "pending", backend = "unknown", base_url = base_url }
end

function M.when_ready(base_url, callback)
    callback(M.get(base_url))
    if type(base_url) == "string" and base_url ~= "" and not snapshots[base_url] then
        waiting[base_url] = waiting[base_url] or {}
        table.insert(waiting[base_url], callback)
    end
end

function M.refresh(base_url, callback)
    if type(base_url) ~= "string" or base_url == "" then
        if callback then callback(M.get(base_url)) end
        return
    end
    local generation = (generations[base_url] or 0) + 1
    generations[base_url] = generation
    snapshots[base_url] = nil -- never retain stale data after a switch or failure
    get_json(base_url .. "/v1/models", function(body)
        local info = body and client.extract_model_info(body)
        local entry = {
            base_url = base_url,
            status = info and "ready" or "fetch_failed",
            actual_model_name = info and info.name or nil,
            actual_model_abbreviation = info and models.abbreviate_actual_model_name(info.name) or nil,
            actual_model_info = info,
            backend = body and detect(body),
        }
        local function finish()
            -- A slower earlier selection must not overwrite a newer probe.
            if generations[base_url] ~= generation then return end
            snapshots[base_url] = entry
            if callback then callback(entry) end
            local callbacks = waiting[base_url] or {}
            waiting[base_url] = nil
            for _, fn in ipairs(callbacks) do fn(entry) end
            vim.api.nvim_exec_autocmds("User", { pattern = "AskOpenAIModelInfoUpdated", data = entry })
        end
        if not body then entry.backend = "unknown"; finish(); return end
        if entry.backend then finish(); return end
        get_json(base_url .. "/props", function(props)
            if props and type(props.default_generation_settings) == "table" then
                entry.backend = "llama-server"
                finish()
                return
            end
            get_json(base_url .. "/openapi.json", function(schema)
                local title = schema and schema.info and schema.info.title
                entry.backend = type(title) == "string" and title:lower():find("vllm", 1, true)
                    and "vllm" or "unknown"
                finish()
            end)
        end)
    end)
end

return M
