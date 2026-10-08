--- Align a model's edit-prediction completion against the current buffer to
--- extract the delta (the genuinely new lines) and where they should insert.
---
--- The edit-prediction contract asks the model to reproduce at least one
--- verbatim context line (an "anchor") immediately before the lines it wants
--- to change. The aligner:
---   1. strips leading/trailing code fences,
---   2. finds the first completion line that exactly matches a buffer line
---      near the cursor (the anchor),
---   3. collects the completion lines after the anchor,
---   4. drops trailing lines that verbatim repeat the buffer lines right after
---      the anchor (so an echo of unchanged context is not re-inserted),
---   5. positions the insertion at the cursor.
---
--- Because the model leads with a verbatim anchor, this is robust to the
--- prefix-echo and fence noise that made the old FIM path brittle.
---
--- @class EditAlignment
local M = {}

---@class EditAligned
---@field anchor_line_base0 integer -- buffer line where the anchor matched
---@field insertion_line_base0 integer -- buffer line to insert at
---@field insertion_col_base0 integer -- buffer column to insert at
---@field insertion_lines string[] -- the new lines to insert

--- Split text into lines, preserving empty lines.
--- @param text string
--- @return string[]
function M.split_lines(text)
    return vim.split(text, "\n", { plain = true })
end

--- Drop a leading ```fence line and a trailing ```fence line (if present).
--- A fence line is only stripped when more content follows/ precedes it, so a
--- lone or partial fence (still streaming) is left alone.
--- @param lines string[]
--- @return string[]
function M.strip_fences(lines)
    local stripped = {}
    for _, line in ipairs(lines) do
        table.insert(stripped, line)
    end
    -- leading fence: first line is exactly "```" or "```lang" with content after
    if #stripped > 1 and stripped[1]:match("^```%S*$") then
        table.remove(stripped, 1)
    end
    -- trailing fence: last line is exactly "```" with content before it
    if #stripped > 1 and stripped[#stripped] == "```" then
        table.remove(stripped, #stripped)
    end
    return stripped
end

--- Search the buffer for an exact line match near the cursor, preferring lines
--- close to the cursor (both before and after, alternating).
--- @param line string
--- @param buffer_lines string[]
--- @param cursor_line_base0 integer
--- @param search_radius_base1 integer
--- @return integer? buffer_line_base0
function M.find_line_in_buffer(line, buffer_lines, cursor_line_base0, search_radius_base1)
    search_radius_base1 = search_radius_base1 or 30
    local low = math.max(0, cursor_line_base0 - search_radius_base1)
    local high = math.min(#buffer_lines - 1, cursor_line_base0 + search_radius_base1)
    for offset = 0, search_radius_base1 do
        local before = cursor_line_base0 - offset
        local after = cursor_line_base0 + offset
        if before >= low and buffer_lines[before + 1] == line then
            return before
        end
        if after <= high and after ~= before and buffer_lines[after + 1] == line then
            return after
        end
    end
    return nil
end

--- Find the first completion line that exactly matches a buffer line near the
--- cursor. Returns the anchor's buffer position and its completion index.
--- @param completion_lines string[]
--- @param buffer_lines string[]
--- @param cursor_line_base0 integer
--- @param search_radius_base1 integer
--- @return integer? anchor_buffer_line_base0
--- @return integer? anchor_completion_index_base1
function M.find_anchor(completion_lines, buffer_lines, cursor_line_base0, search_radius_base1)
    for completion_index_base1, line in ipairs(completion_lines) do
        -- empty lines are never useful anchors (they match too many places)
        if line ~= "" then
            local buffer_line_base0 = M.find_line_in_buffer(
                line, buffer_lines, cursor_line_base0, search_radius_base1)
            if buffer_line_base0 then
                return buffer_line_base0, completion_index_base1
            end
        end
    end
    return nil, nil
end

--- Drop trailing delta lines that verbatim repeat the anchor line or the buffer
--- lines that follow it. This removes an echo of unchanged context so it is not
--- re-inserted.
--- @param delta_lines string[]
--- @param buffer_lines string[]
--- @param anchor_buffer_line_base0 integer
--- @return string[]
function M.trim_repeated_suffix(delta_lines, buffer_lines, anchor_buffer_line_base0)
    local trimmed = {}
    for _, line in ipairs(delta_lines) do
        table.insert(trimmed, line)
    end
    -- Candidate lines the model may have echoed: the anchor line itself plus
    -- every buffer line after it.
    local echoable = { buffer_lines[anchor_buffer_line_base0 + 1] }
    for i = anchor_buffer_line_base0 + 2, #buffer_lines do
        table.insert(echoable, buffer_lines[i])
    end
    while #trimmed > 0 and vim.tbl_contains(echoable, trimmed[#trimmed]) do
        table.remove(trimmed, #trimmed)
    end
    return trimmed
end

--- Align a completion against the buffer near the cursor.
--- @param completion_text string
--- @param buffer_lines string[]
--- @param cursor_line_base0 integer
--- @param cursor_col_base0 integer
--- @return EditAligned? edit
function M.align(completion_text, buffer_lines, cursor_line_base0, cursor_col_base0)
    local completion_lines = M.strip_fences(M.split_lines(completion_text))

    local anchor_buffer_line_base0, anchor_completion_index_base1 = M.find_anchor(
        completion_lines, buffer_lines, cursor_line_base0)

    if not anchor_buffer_line_base0 then
        return nil
    end

    -- The delta: completion lines after the anchor.
    local delta_lines = {}
    for i = anchor_completion_index_base1 + 1, #completion_lines do
        table.insert(delta_lines, completion_lines[i])
    end

    delta_lines = M.trim_repeated_suffix(delta_lines, buffer_lines, anchor_buffer_line_base0)

    -- Position: if the anchor is the cursor line, insert at the cursor column;
    -- otherwise insert a new line right after the anchor.
    local insertion_line_base0 = anchor_buffer_line_base0
    local insertion_col_base0 = 0
    if anchor_buffer_line_base0 == cursor_line_base0 then
        insertion_col_base0 = cursor_col_base0
    else
        insertion_line_base0 = anchor_buffer_line_base0 + 1
    end

    return {
        anchor_line_base0 = anchor_buffer_line_base0,
        insertion_line_base0 = insertion_line_base0,
        insertion_col_base0 = insertion_col_base0,
        insertion_lines = delta_lines,
    }
end

return M
