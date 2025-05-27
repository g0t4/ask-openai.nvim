local function tokenize(code)
    -- Basic tokenizer: split on whitespace, remove comments and normalize
    local tokens = {}
    -- Remove Lua comments (-- and --[[ ... ]])
    code = code:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    -- Split on whitespace and normalize
    for token in code:gmatch("%S+") do
        table.insert(tokens, token:lower()) -- Normalize to lowercase
    end
    return tokens
end

local function get_shingles(tokens, k)
    -- Generate k-shingles from tokens
    local shingles = {}
    for i = 1, #tokens - k + 1 do
        local shingle = table.concat({ unpack(tokens, i, i + k - 1) }, " ")
        shingles[shingle] = true
    end
    return shingles
end

local function simple_hash(s)
    -- Simple string hash function
    local hash = 0
    for i = 1, #s do
        hash = (hash * 31 + string.byte(s, i)) % 2 ^ 32
    end
    return hash
end

local function minhash(shingles, num_hashes)
    -- Generate MinHash signature
    local signature = {}
    for i = 1, num_hashes do
        local min_hash = math.huge
        for shingle, _ in pairs(shingles) do
            -- Use different seeds for each hash function
            local h = simple_hash(shingle .. i)
            if h < min_hash then min_hash = h end
        end
        table.insert(signature, min_hash)
    end
    return signature
end

local function jaccard_similarity(sig1, sig2)
    -- Compute Jaccard similarity of two MinHash signatures
    local matches = 0
    for i = 1, #sig1 do
        if sig1[i] == sig2[i] then matches = matches + 1 end
    end
    return matches / #sig1
end

local function detect_near_duplicates(yanks, k, num_hashes, threshold)
    -- Detect near duplicates in a list of code snippets
    local signatures = {}
    -- Generate MinHash signatures for each yank
    for i, yank in ipairs(yanks) do
        local tokens = tokenize(yank)
        local shingles = get_shingles(tokens, k)
        signatures[i] = minhash(shingles, num_hashes)
    end
    -- Compare signatures and find near duplicates
    local duplicates = {}
    for i = 1, #yanks do
        for j = i + 1, #yanks do
            local similarity = jaccard_similarity(signatures[i], signatures[j])
            if similarity >= threshold then
                table.insert(duplicates, {i, j, similarity})
            end
        end
    end
    return duplicates
end

describe("Duplicate detection tests", function()
    it("should correctly find near duplicate code snippets", function()
        -- Example usage
        local yanks = {
            "function add(a, b) return a + b end",
            "function add(x, y) return x + y end", -- Near duplicate
            "function multiply(a, b) return a * b end",
        }
        local k = 3 -- Shingle size
        local num_hashes = 20 -- Number of hash functions
        local threshold = 0.8 -- Similarity threshold

        local duplicates = detect_near_duplicates(yanks, k, num_hashes, threshold)
        for _, dup in ipairs(duplicates) do
            print(string.format("Yanks %d and %d are near duplicates (similarity: %.2f)", dup[1], dup[2], dup[3]))
        end
    end)
end)
