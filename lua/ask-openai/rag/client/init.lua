local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.prediction.ansi")

local M = {}

local function check_supported_dirs()
    local cwd = vim.fn.getcwd()
    local dot_rag_dir = cwd .. "/.rag"

    local is_rag_dir = files.exists(dot_rag_dir)

    if not is_rag_dir then
        -- fallback check git repo root
        --   i.e. the rag dir in this ask-openai repo, or my hammerspoon config in my dotfiles repo
        --   I often work inside these directories, maybe I should just have a .rag dir in them too.. and scope to just it but maybe not?
        local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
        dot_rag_dir = git_root .. "/.rag"
        is_rag_dir = files.exists(dot_rag_dir)
        if not is_rag_dir then
            log:info("RAG is disabled b/c there is NO .rag dir: " .. dot_rag_dir)
            return
        end
        log:info("fallback, found .rag in repo root: " .. git_root .. "/.rag")
    end

    M.is_rag_indexed_workspace = is_rag_dir
    M.rag_extensions = files.list_directories(dot_rag_dir)
    log:info("RAG is supported for: " .. vim.inspect(M.rag_extensions))
end
check_supported_dirs()

function M.get_filetypes_for_workspace()
    -- FYI vim filetypes for enabling the LSP client for RAG purposes
    local ext_to_filetype = {
        -- extension = filetype
        bash = "sh", -- *
        clj = "clojure",
        coffee = "coffeescript",
        conf = "cfg",
        cs = "csharp",
        h = "c",
        hh = "cpp",
        hpp = "cpp",
        hs = "haskell",
        htm = "html",
        jade = "pug",
        js = "javascript", -- *
        julia = "julia",
        kt = "kotlin",
        lhs = "lhaskell",
        m = "objc", -- others for objc?
        mm = "objc",
        md = "markdown", -- *
        pl = "perl",
        pm = "perl",
        py = "python", -- *
        rb = "ruby",
        rs = "rust",
        scm = "scheme",
        shtml = "html",
        swift = "swift",
        ts = "typescript",
        tsx = "typescriptreact",
        vimrc = "vim",
        yml = "yaml", -- *
    }

    return vim.iter(M.rag_extensions or {})
        :map(function(ext) return ext_to_filetype[ext] or ext end)
        :totable()
end

function M.is_rag_supported_in_current_file()
    if not M.is_rag_indexed_workspace then
        return false
    end

    local current_file_extension = vim.fn.expand("%:e")
    return vim.tbl_contains(M.rag_extensions, current_file_extension)
end

---@param str string
---@return string
function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

---@param ps_chunk PrefixSuffixChunk
---@returns string? -- FIM query string, or nil to disable FIM Semantic Grep
local function fim_concat(ps_chunk)
    -- FYI see fim_query_notes.md for past and future ideas for Semantic Grep selection w.r.t. RAG+FIM

    -- * TESTING FIM+RAG with cursor line ONLY for query
    local query = ps_chunk.rag_cursor_line_before_cursor

    if trim(query) == "" then
        -- log:trace(ansi.white_bold(ansi.red_bg("SKIPPING Semantic Grep b/c no query (nothing on cursor line before cursor)")))
        -- PRN previous line? with a non-empty value? if so, pass all lines or a subset from ps_chunk builder (on ps_chunk)
        return nil
    end

    log:trace(string.format("fim_concat: query=%q", query))
    return query
end

---@enum ChunkType
local ChunkType = {
    LINES = "lines",
    TREESITTER = "ts",
    UNCOVERED_CODE = "uncovered",
}

---@class LSPSemanticGrepRequest
---@field query string
---@field vimFiletype string
---@field currentFileAbsolutePath string
---@field instruct? string
---@field languages? string
---@field skipSameFile? boolean
---@field topK? integer
---@field embedTopK? integer
_G.LSPSemanticGrepRequest = {}


---@class LSPSemanticGrepResult
---@field matches LSPRankedMatch[]
---@field error? string
_G.LSPSemanticGrepResult = {}

---@class LSPRankedMatch
---@field text string
---@field file string
---@field start_line_base0 integer
---@field start_column_base0 integer
---@field end_line_base0 integer
---@field end_column_base0 integer|nil
---@field type ChunkType
---@field embed_score number
---@field rerank_score number
---@field embed_rank integer
---@field rerank_rank integer
---@field signature string
_G.LSPRankedMatch = {}

---@param user_prompt string
---@param code_context string
---@param callback fun(matches: LSPRankedMatch[], failed: boolean)
function M.context_query_rewrites(user_prompt, code_context, callback)
    -- FYI use user message for now as Instruct and selected code as the Query
    local query = code_context
    local instruct = user_prompt
    -- TODO! pass line ranges for limiting same file skips
    return M._context_query(query, instruct, callback)
end

---@param ps_chunk PrefixSuffixChunk
---@param callback fun(matches: LSPRankedMatch[], failed: boolean)
---@param skip_rag fun()
function M.context_query_fim(ps_chunk, callback, skip_rag)
    local fim_specific_instruct = "Complete the missing portion of code (FIM) based on the surrounding context (Fill-in-the-middle)"
    local query = fim_concat(ps_chunk)
    if query == nil then
        skip_rag()
        return
    end
    -- PRN pass fim.semantic_grep.all_files settings (create an options object and pass that instead of a dozen args)
    -- PRN pass ps_chunk start/end lines to limit same file skips
    return M._context_query(query, fim_specific_instruct, callback)
end

---@param query string # Query section only, no Instruct/Document
---@param instruct string # Instruct section only
---@param callback fun(matches: LSPRankedMatch[], failed: boolean)
function M._context_query(query, instruct, callback)
    ---@type LSPSemanticGrepRequest
    local semantic_grep_request = {
        query = query,
        instruct = instruct,
        currentFileAbsolutePath = files.get_current_file_absolute_path(),
        vimFiletype = vim.bo.filetype,
        skipSameFile = true,
        topK = 5, -- TODO what do I want for FIM vs REWRITE? maybe a dial too?
        embedTopK = 18, -- consider more so that re-ranker picks topK best matches
        -- TODO pass line range for same file to allow outside that range
        -- FYI some rewrites I might not want ANY RAG... maybe no context too
        -- PRN other file types? languages=all? knob too?
    }

    local _client_request_ids, _cancel_all_requests -- declare in advance for closure:

    ---@param result LSPSemanticGrepResult
    function on_server_response(err, result)
        -- FYI do your best to log errors here so that code is not duplicated downstream
        if err then
            vim.notify("Semantic Grep failed: " .. err.message, vim.log.levels.ERROR)
            callback({}, true) -- still callback w/ no results
            return
        end

        if result.error ~= nil and result.error ~= "" then
            log:error("RAG response error, still calling back: ", vim.inspect(result))
            -- in the event matches are still returned, process them too... if server returns matches, use them!
            callback(result.matches or {}, true)
            return
        end
        log:info(ansi.white_bold(ansi.red_bg("RAG matches (client):")), vim.inspect(result))
        callback(result.matches or {}, false)
    end

    local params = {
        command = "semantic_grep",
        -- arguments is an array table, not a dict type table (IOTW only keys are sent if you send a k/v map)
        arguments = { semantic_grep_request },
    }

    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, on_server_response)
    return _client_request_ids, _cancel_all_requests
end

return M
