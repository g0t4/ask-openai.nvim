local M = {}

M.codellama = {
    -- codellama template:
    --    {{- if .Suffix }}<PRE> {{ .Prompt }} <SUF>{{ .Suffix }} <MID>
    sentinel_tokens = {
        fim_prefix = "<PRE> ",
        fim_suffix = " <SUF>",
        fim_middle = " <MID>",
    },
}

return M
