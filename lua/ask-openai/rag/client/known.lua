local embeddings_client = require("ask-openai.rag.client.embedder")

local M = {}

--- Expected similarity scores for known embeddings by model identifier.
--- This table is now exposed publicly via the module for testing purposes.
M.expected_scores_by_model_identifier = {
    ["Qwen/Qwen3-Embedding-0.6B"] = { { 0.7646, 0.1414 }, { 0.1355, 0.6000 } },
    ["Qwen/Qwen3-Embedding-4B"]   = { { 0.7534, 0.1147 }, { 0.0320, 0.6258 } },
    ["Qwen/Qwen3-Embedding-8B"]   = { { 0.7493, 0.0751 }, { 0.0880, 0.6318 } },
}

print("FYI compare outputs to python outputs, i.e. lengths should match...")

---@return string[] input_texts
function M.get_known_inputs()
    local instruct = "Given a web search query, retrieve relevant passages that answer the query"

    local queries = {
        embeddings_client.qwen3_format_query("What is the capital of China?", instruct),
        embeddings_client.qwen3_format_query("Explain gravity", instruct),
    }

    local documents = {
        "The capital of China is Beijing.",
        "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
    }

    local input_texts = vim.list_extend({}, queries)
    vim.list_extend(input_texts, documents)

    -- prints for padding checks:
    for i, text in ipairs(input_texts) do
        print(string.format("%d: %s", i - 1, ("len(text)=%d"):format(#text)))
    end

    return input_texts
end

--- Compute the dot‑product matrix between two sets of vectors.
---@param a number[][] left‑hand side (m × d)
---@param b number[][] right‑hand side (n × d)
---@return number[][] m × n matrix where entry (i, j) = a[i]·b[j]
local function dot_product_matrix(a, b)
    local m = #a
    local n = #b
    local result = {}
    for i = 1, m do
        result[i] = {}
        for j = 1, n do
            local sum = 0
            for k = 1, #a[i] do
                sum = sum + a[i][k] * b[j][k]
            end
            result[i][j] = sum
        end
    end
    return result
end

--- Compare two matrices element‑wise with a tolerance.
---@param actual number[][]
---@param expected number[][]
---@param decimal integer number of decimal places to keep (default 3)
local function assert_matrices_almost_equal(actual, expected, decimal)
    decimal = decimal or 3
    local eps = 10 ^ -decimal
    for i = 1, #actual do
        for j = 1, #actual[i] do
            local diff = math.abs(actual[i][j] - expected[i][j])
            if diff > eps then
                error(string.format(
                    "Matrix mismatch at (%d,%d): actual=%f expected=%f diff=%f > %f",
                    i, j, actual[i][j], expected[i][j], diff, eps
                ))
            end
        end
    end
end

---@param embeddings number[][] embeddings returned by `embed_batch`
local function assert_known_embeddings_match_expected_scores(embeddings)
    -- First two vectors correspond to queries, the remaining to passages.
    local query_embeddings = { embeddings[1], embeddings[2] }
    local document_embeddings = { embeddings[3], embeddings[4] }

    -- Compute similarity matrix (queries × passages).
    local actual_scores = dot_product_matrix(query_embeddings, document_embeddings)

    local model_identifier = "Qwen/Qwen3-Embedding-0.6B"

    ---@type table<string, number[][]>
    local expected_scores = M.expected_scores_by_model_identifier[model_identifier]
    if not expected_scores then
        error(string.format("cannot find expected scores for %s", model_identifier))
    end

    assert_matrices_almost_equal(actual_scores, expected_scores, 3)

    print(string.format("  actual_scores=%s", vim.inspect(actual_scores)))
    print(string.format("  expected_scores=%s", vim.inspect(expected_scores)))
    print("[green bold]scores look ok")
end

---@return boolean ok
function M.run_verification()
    local known_inputs = M.get_known_inputs()
    -- vim.print('inputs:', known_inputs)
    local embeddings, err = embeddings_client.embed_batch(known_inputs)
    -- vim.print('embeddings:', embeddings)
    if not embeddings then
        print("Embedding request failed: " .. (err or "unknown error"))
        return false
    end

    local ok, verify_err = pcall(assert_known_embeddings_match_expected_scores, embeddings)
    if not ok then
        print("Verification failed: " .. verify_err)
        return false
    end

    return true
end

return M
