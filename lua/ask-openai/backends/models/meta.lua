local M = {}

local function codellama_tag(name)
    return "<" .. name .. ">"
end
M.codellama = {
    -- codellama template:
    --    {{- if .Suffix }}(codellama.PRE) {{ .Prompt }} (codellama.SUF){{ .Suffix }} (codellama.MID)
    sentinel_tokens = {
        FIM_PREFIX = codellama_tag("PRE") .. " ", -- space after
        FIM_SUFFIX = " " .. codellama_tag("SUF"), -- space before
        FIM_MIDDLE = " " .. codellama_tag("MID"), -- space before
        EOT = codellama_tag("EOT"),
    },
}

return M
