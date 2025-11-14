local M = {}

---@param rag_matches LSPRankedMatch[]
---@return LSPRankedMatch[]
function M.merge_contiguous_chunks(rag_matches)
    local matches_by_file = {}
    for _, match in ipairs(rag_matches) do
        if not matches_by_file[match.file] then matches_by_file[match.file] = {} end
        table.insert(matches_by_file[match.file], match)
    end
    local merged_chunks = {}
    for file, matches in pairs(matches_by_file) do
        table.sort(matches, function(a, b) return a.start_line_base0 < b.start_line_base0 end)
        local current_chunk = nil
        for _, match in ipairs(matches) do
            if not current_chunk then
                current_chunk = {
                    file = file,
                    start_line_base0 = match.start_line_base0,
                    end_line_base0 = match.end_line_base0,
                    text = match.text,
                }
            else
                local is_overlap = match.start_line_base0 <= current_chunk.end_line_base0 + 1
                if is_overlap then
                    if match.end_line_base0 > current_chunk.end_line_base0 then
                        current_chunk.end_line_base0 = match.end_line_base0
                    end
                    current_chunk.text = current_chunk.text .. "\n" .. match.text
                else
                    table.insert(merged_chunks, current_chunk)
                    current_chunk = {
                        file = file,
                        start_line_base0 = match.start_line_base0,
                        end_line_base0 = match.end_line_base0,
                        text = match.text,
                    }
                end
            end
        end
        if current_chunk then table.insert(merged_chunks, current_chunk) end
    end
    return merged_chunks
end

return M
