local M = {}

---@param chunk LSPRankedMatch
---@return LSPRankedMatch
function M.clone_chunk(chunk)
    local copy = {}
    for k, v in pairs(chunk) do
        copy[k] = v
    end
    return copy
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
            if not current_chunk then
                -- current as in we are merging subsequent chunks until nothing overlaps/touches
                current_chunk = M.clone_chunk(next_chunk)
            else
                -- TODO add test case of overlap
                -- TODO add test case of touch (and check math here for + 1):
                local overlap_or_touch = next_chunk.start_line_base0 <= current_chunk.end_line_base0 + 1

                if overlap_or_touch then
                    if next_chunk.end_line_base0 > current_chunk.end_line_base0 then
                        current_chunk.end_line_base0 = next_chunk.end_line_base0
                    end
                    -- TODO fix logic for merging text! need to consider overlapping and remove the overlapping (not duplicate them)
                    --   USE A UNIT TEST TO FIX THIS! careful! this is almost impossible to test otherwise!
                    current_chunk.text = current_chunk.text .. "\n" .. next_chunk.text
                else
                    table.insert(merged_chunks, current_chunk)
                    current_chunk = M.clone_chunk(next_chunk)
                end
            end
        end
        if current_chunk then table.insert(merged_chunks, current_chunk) end
    end
    return merged_chunks
end

return M
