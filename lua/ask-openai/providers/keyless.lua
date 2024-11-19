---@return string
local function get_bearer_token()
    -- TODO address keyless s/b empty but I check not empty in consumer
    return "foo" -- doesn't matter, i.e. ollama
end

return {
    get_bearer_token = get_bearer_token,
}
