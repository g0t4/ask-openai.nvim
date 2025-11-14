local M = {}

---@param chunk LSPRankedMatch
---@return LSPRankedMatch
function M.clone_chunk(chunk)
    -- TODO anything I don't want to clone:
    return {
        -- TODO did I miss any fields (gptoss used RAG to get this list => probably used LSPRankedMatch definition, check to make sure that is complete)
        text = chunk.text,
        file = chunk.file,
        start_line_base0 = chunk.start_line_base0,
        start_column_base0 = chunk.start_column_base0,
        end_line_base0 = chunk.end_line_base0,
        end_column_base0 = chunk.end_column_base0,
        type = chunk.type,
        -- TODO do I even use scores/ranks in areas where I want to use this merge? I don't think so
        --  if not, just skip entirely for now, leave this here in case you want to add later is fine
        -- embed_score = chunk.embed_score,
        -- rerank_score = chunk.rerank_score,
        -- embed_rank = chunk.embed_rank,
        -- rerank_rank = chunk.rerank_rank,
        -- signature = chunk.signature,
    }
    -- local copy = {}
    -- for k, v in pairs(chunk) do
    --     copy[k] = v
    -- end
    -- return copy
end

---@param rag_matches LSPRankedMatch[]
---@return LSPRankedMatch[]
function M.merge_contiguous_rag_chunks(rag_matches)
    -- merge chunks that overlap OR touch (end line == start line)
    --   often from ts_chunk and line range overlap

    -- TODO USE THIS IN ALL RAG_MATCH SPOTS:
    -- - AskRewrite
    -- - Predictions (various models)
    -- - etc

    -- * group by file
    local matches_by_file = {}
    for _, match in ipairs(rag_matches) do
        if not matches_by_file[match.file] then matches_by_file[match.file] = {} end
        table.insert(matches_by_file[match.file], match)
    end

    local merged_chunks = {}
    for file, matches in pairs(matches_by_file) do
        table.sort(matches, function(a, b) return a.start_line_base0 < b.start_line_base0 end)

        local current_chunk = nil
        for _, next_chunk in ipairs(matches) do
            -- ACCUMULATOR pattern => left to right, merge left
            if not current_chunk then
                -- current as in we are merging subsequent chunks until nothing overlaps/touches
                current_chunk = M.clone_chunk(next_chunk)
                table.insert(merged_chunks, current_chunk)
            else
                -- TODO add test case of overlap
                -- TODO add test case of touch (and check math here for + 1):
                local overlap_or_touch = next_chunk.start_line_base0 <= current_chunk.end_line_base0 + 1

                if overlap_or_touch then
                    current_chunk.end_line_base0 = math.max(current_chunk.end_line_base0, next_chunk.end_line_base0)

                    -- TODO! fix logic for merging text! need to consider overlapping and remove the overlapping (not duplicate them)
                    --   USE A UNIT TEST TO FIX THIS! careful! this is almost impossible to test otherwise!
                    current_chunk.text = current_chunk.text .. "\n" .. next_chunk.text
                else
                    -- proceed to next chunk
                    current_chunk = M.clone_chunk(next_chunk)
                    table.insert(merged_chunks, current_chunk)
                end
            end
        end
    end
    return merged_chunks
end

return M
