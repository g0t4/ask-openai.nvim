---@mod ask-openai.rag.client.known Known inputs and verification for Qwen‑3 embeddings
---@brief
-- Provides a helper that builds the same inputs used in the Python
-- reference implementation and a verification routine that checks the
-- returned embeddings against the expected scores.
--
-- The module relies on the public API defined in
-- `ask-openai.rag.client.embeddings` (`embed_batch`).

local embeddings_client = require("ask-openai.rag.client.embeddings")

local M = {}

--- Build the list of queries (with instruction) and reference documents.
---@return string[] input_texts
function M.get_known_inputs()
    local instruct = "Given a web search query, retrieve relevant passages that answer the query"

    -- Helper to format a query for Qwen‑3.  The original Python code used a
    -- function `qwen3_format_query`; we inline the same behaviour here.
    local function qwen3_format_query(query, instruction)
        return instruction .. "\n" .. query
    end

    local queries = {
        qwen3_format_query("What is the capital of China?", instruct),
        qwen3_format_query("Explain gravity", instruct),
    }

    local documents = {
        "The capital of China is Beijing.",
        "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
    }

    local input_texts = {}
    for _, q in ipairs(queries) do
        table.insert(input_texts, q)
    end
    for _, d in ipairs(documents) do
        table.insert(input_texts, d)
    end

    -- Print length information for debugging / padding checks.
    for i, text in ipairs(input_texts) do
        print(string.format("%d: %s", i - 1, ("len(text)=%d"):format(#text)))
    end

    return input_texts
end

--- Expected similarity scores for each model path.
---@type table<string, number[][]>
local expected_scores_by_model_path = {
    ["Qwen/Qwen3-Embedding-0.6B"] = { { 0.7646, 0.1414 }, { 0.1355, 0.6000 } },
    ["Qwen/Qwen3-Embedding-4B"]   = { { 0.7534, 0.1147 }, { 0.0320, 0.6258 } },
    ["Qwen/Qwen3-Embedding-8B"]   = { { 0.7493, 0.0751 }, { 0.0880, 0.6318 } },
}

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

--- Verify that embeddings produced for the known inputs match the
--- pre‑computed scores for a given model.
---@param embeddings number[][] embeddings returned by `embed_batch`
---@param model_path string model identifier (e.g. "Qwen/Qwen3-Embedding-4B")
local function verify_qwen3_known_embeddings(embeddings, model_path)
    -- First two vectors correspond to queries, the remaining to passages.
    local query_embeddings = { embeddings[1], embeddings[2] }
    local passage_embeddings = { embeddings[3], embeddings[4] }

    -- Compute similarity matrix (queries × passages).
    local actual_scores = dot_product_matrix(query_embeddings, passage_embeddings)

    local expected_scores = expected_scores_by_model_path[model_path]
    if not expected_scores then
        error(string.format("cannot find expected scores for %s", model_path))
    end

    print(string.format("expected_scores=%s", vim.inspect(expected_scores)))

    assert_matrices_almost_equal(actual_scores, expected_scores, 3)

    print(string.format("  actual_scores=%s", vim.inspect(actual_scores)))
    print(string.format("  expected_scores=%s", vim.inspect(expected_scores)))
    print("[green bold]scores look ok")
end

--- High‑level helper that obtains the known inputs, queries the embedding
--- server and runs the verification for a given model.
---@param model_path string model identifier used to select expected scores
---@return boolean ok true on success, false on failure
function M.run_verification(model_path)
    local inputs = M.get_known_inputs()
    local embeddings, err = embeddings_client.embed_batch(inputs)
    if not embeddings then
        print("Embedding request failed: " .. (err or "unknown error"))
        return false
    end

    local ok, verify_err = pcall(verify_qwen3_known_embeddings, embeddings, model_path)
    if not ok then
        print("Verification failed: " .. verify_err)
        return false
    end

    return true
end

return M
