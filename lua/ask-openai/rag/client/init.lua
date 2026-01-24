local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.predictions.ansi")
local safely = require("ask-openai.helpers.safely")

local M = {}

---@class RagYamlConfig
---@field enabled boolean

---@param work_dir string
---@return RagYamlConfig?
local function load_rag_yaml_config(work_dir)
    -- FYI
    -- luarocks install --lua-version=5.1  lyaml

    local rag_yaml_path = work_dir .. "/.rag.yaml"
    if not files.exists(rag_yaml_path) then
        log:info("no .rag.yaml found at", rag_yaml_path)
        return nil
    end

    local yaml_content = vim.fn.readfile(rag_yaml_path)
    if not yaml_content then
        error("failed to read file contents", rag_yaml_path)
        return nil
    end

    local yaml_str = table.concat(yaml_content, "\n")
    local ok, parsed = safely.decode_yaml(yaml_str)
    if not ok then
        error("Failed to parse yaml" .. rag_yaml_path)
        return nil
    end

    ---@type RagYamlConfig
    local parsed_config = parsed or {}

    -- AS NEEDED load defaults
    if parsed_config.enabled == nil then
        parsed_config.enabled = true
    end
    return parsed_config
end

local function check_supported_dirs()
    local work_dir = vim.fn.getcwd()
    local dot_rag_dir = work_dir .. "/.rag"

    local is_rag_dir = files.exists(work_dir)
    M.rag_yaml = load_rag_yaml_config(work_dir)
    -- log:info("RAG", vim.inspect(M.rag_yaml))

    if M.rag_yaml and not M.rag_yaml.enabled then
        log:error("RAG is disabled in .rag.yaml")
        return
    end

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
        patch = "diff",
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

function M.is_rag_supported()
    if M.rag_yaml and not M.rag_yaml.enabled then
        -- FYI this was a rushed addition, to toggle RAG on/off in .rag.yaml...
        --   don't be surprised if you have to fix some bugs
        --   I didn't care to spend too much time making sure this was done "right"
        return false
    end
    return M.is_rag_indexed_workspace == true
end

function M.is_rag_supported_in_current_file(bufnr)
    -- TODO add a virtual toggle so LSP failure stops requests too
    --   can I detect non-connected LSP (w/o hugh perf hit?)

    if not M.is_rag_supported() then
        return false
    end

    bufnr = bufnr or 0
    local buffer_name = vim.api.nvim_buf_get_name(bufnr)
    local extension = vim.fn.fnamemodify(buffer_name, ":e")
    -- TODO use filetype instead?
    --  i.e. .yaml/.yml
    --  or c: .h/.c/.cpp ...
    --  or node: .js/.mjs
    return vim.tbl_contains(M.rag_extensions, extension)
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
    local query = ps_chunk.cursor_line.before_cursor

    -- TODO add last user message custom instructions based on cursor_line situation for FIM...
    --     in middle of line => suggest intra line completion, rarely multiline
    --     at end of line => suggest finish current line and/or multiline
    --     blank line => suggest multiline

    if trim(query) == "" then
        local few_before_text = table.concat(ps_chunk.cursor_line.few_lines_before or {}, "\n") or ""
        if vim.trim(few_before_text) ~= "" then
            query = few_before_text
        else
            log:trace(ansi.white_bold(ansi.red_bg("SKIPPING RAG in FIM b/c cursor line is empty (before cursor) and nothing in a few lines above either")))
            -- PRN allow suffix if empty prefix line? OR take a few lines around it?
            -- PRN previous line? with a non-empty value? if so, pass all lines or a subset from ps_chunk builder (on ps_chunk)
            return nil
        end
    end

    -- log:trace(string.format("fim_concat: query=%q", query))
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
---@field start_column_base0 integer|nil
---@field end_line_base0 integer
---@field end_column_base0 integer|nil
---@field type ChunkType
---@field embed_score number
---@field rerank_score number
---@field embed_rank integer
---@field rerank_rank integer
---@field signature string
_G.LSPRankedMatch = {}

---@param same_file_bufnr integer - chat window will pooch finding current filename/type, so pass bufnr to use for same file lookup
---@param user_prompt string
---@param code_context? string
---@param top_k? integer
---@param callback fun(matches: LSPRankedMatch[])
function M.context_query_questions(same_file_bufnr, user_prompt, code_context, top_k, callback)
    top_k = top_k or 5
    local file = vim.api.nvim_buf_get_name(same_file_bufnr)
    -- PRN do something else when no code_context (nothing selected intentionally by user)?
    local query = code_context or ("I have this file open: " .. file)

    ---@type LSPSemanticGrepRequest
    local request = {
        query = query,
        instruct = user_prompt,

        currentFileAbsolutePath = file,
        vimFiletype = vim.bo[same_file_bufnr].filetype,
        skipSameFile = true, -- PRN allow same file, i.e. if no code_context (and not including entire file)
        -- TODO pass line ranges for limiting same file skips

        topK = top_k,
        embedTopK = top_k * 4,
    }
    return M._context_query(request, callback)
end

---@param user_prompt string
---@param code_context string
---@param top_k? integer
---@param callback fun(matches: LSPRankedMatch[])
function M.context_query_rewrites(user_prompt, code_context, top_k, callback)
    top_k = top_k or 5
    ---@type LSPSemanticGrepRequest
    local request = {
        query = code_context,
        instruct = user_prompt,
        -- very happy w/ instruct==user_prompt + query=selected_code

        currentFileAbsolutePath = files.get_current_file_absolute_path(),
        vimFiletype = vim.bo.filetype,
        skipSameFile = true,
        -- TODO pass line ranges for limiting same file skips

        topK = top_k,
        embedTopK = top_k * 4,
        -- very happy w/ AskRewrite rag_matches w/ top_k=5 + embed_top_k=18
    }
    return M._context_query(request, callback)
end

---@param ps_chunk PrefixSuffixChunk
---@param callback fun(matches: LSPRankedMatch[])
function M.context_query_fim(ps_chunk, callback)
    -- FYI IIRC I put the query building here to consolidate query/instruct logic across frontends
    --   it would be fine to push this out into PredictionsFrontend too...

    local fim_specific_instruct = "Complete the missing portion of code (FIM) based on the surrounding context (Fill-in-the-middle)"
    local query = fim_concat(ps_chunk)
    if query == nil then
        callback({}) -- no results if no query (not a failure)
        return
    end

    -- PRN pass fim.semantic_grep.all_files settings (create an options object and pass that instead of a dozen args)
    -- TODO! pass ps_chunk start/end (line range) to limit same file skips
    ---@type LSPSemanticGrepRequest
    local request = {
        query = query,
        instruct = fim_specific_instruct,
        currentFileAbsolutePath = files.get_current_file_absolute_path(),
        vimFiletype = vim.bo.filetype,
        skipSameFile = true,
        topK = 5,
        embedTopK = 18,
    }
    return M._context_query(request, callback)
end

---@param request LSPSemanticGrepRequest
---@param callback fun(matches: LSPRankedMatch[])
function M._context_query(request, callback)
    local _client_request_ids, _cancel_all_requests -- declare in advance for closure:

    ---@param result LSPSemanticGrepResult
    local function on_server_response(err, result)
        -- FYI do your best to log errors here so that code is not duplicated downstream
        if err then
            vim.notify("Semantic Grep failed: " .. err.message, vim.log.levels.ERROR)
            callback({}) -- still callback w/ no results
            return
        end

        if result.error ~= nil and result.error ~= "" then
            if result.error == "Client cancelled query" then
                -- do not log if its just a cancel (this is my server side error)
                -- no caller would need to get a callback in this case
                -- ?? maybe the server should not even bother responding?
                return
            end
            log:error("RAG response error, still calling back: ", vim.inspect(result))

            -- in the event matches are still returned, process them too... if server returns matches, use them!
            callback(result.matches or {})
            return
        end
        -- log:info(ansi.white_bold(ansi.red_bg("RAG matches (client):")), vim.inspect(result))
        -- TODO use log_semantic_grep_matches(result) instead of luaify_trace/vim.inspect ... move the func and make it useful here
        callback(result.matches or {})
    end

    log:error("_context_query.request", vim.inspect(request)) -- TODO comment out later
    local params = {
        command = "semantic_grep",
        -- arguments is an array table, not a dict type table (IOTW only keys are sent if you send a k/v map)
        arguments = { request },
    }

    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, on_server_response)
    return _client_request_ids, _cancel_all_requests
end

return M
