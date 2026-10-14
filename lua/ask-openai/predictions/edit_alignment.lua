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
---   4. drops leading/trailing lines that verbatim repeat the buffer lines
---      right after the anchor (so echoes of unchanged context are not
---      re-inserted),
---   5. positions the edit at the cursor, computing a replacement span when
---      the delta replaces existing buffer lines rather than inserting.
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
---@field replace_start_line_base0? integer -- buffer line to replace from (nil = pure insert)
---@field replace_start_col_base0? integer -- buffer column to replace from
---@field replace_end_line_base0? integer -- buffer line to replace to (exclusive)
---@field replace_end_col_base0? integer -- buffer column to replace to (exclusive)
---@field trailing_echo_end_line_base0? integer -- last line of the echoed context (exclusive)

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

    -- trailing fence: last line is exactly "```", possibly followed by blank
    -- lines (e.g. a trailing "\n" after the closing fence). Peek past them.
    local trailing_blanks = 0
    while #stripped > 0 and stripped[#stripped] == "" do
        trailing_blanks = trailing_blanks + 1
        table.remove(stripped, #stripped)
    end
    if #stripped > 0 and stripped[#stripped] == "```" then
        -- remove the fence and discard the trailing blank lines (wrapper noise)
        table.remove(stripped, #stripped)
    else
        -- no trailing fence; restore the blank lines (they may be real content)
        for _ = 1, trailing_blanks do
            table.insert(stripped, "")
        end
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

--- Build the buffer lines immediately following the anchor (0-based index
--- anchor+1 onwards). Used for leading echo matching.
--- @param buffer_lines string[]
--- @param anchor_buffer_line_base0 integer
--- @return string[] buffer_context
local function buffer_context_after_anchor(buffer_lines, anchor_buffer_line_base0)
    local buffer_context = {}
    for i = anchor_buffer_line_base0 + 2, #buffer_lines do
        table.insert(buffer_context, buffer_lines[i])
    end
    return buffer_context
end

--- Build the buffer lines for trailing echo matching. Starts at the anchor line
--- itself (the model may echo it after the change) and continues to the end.
--- @param buffer_lines string[]
--- @param anchor_buffer_line_base0 integer
--- @return string[] buffer_context
local function buffer_context_for_trailing_echo(buffer_lines, anchor_buffer_line_base0)
    local buffer_context = {}
    for i = anchor_buffer_line_base0 + 1, #buffer_lines do
        table.insert(buffer_context, buffer_lines[i])
    end
    return buffer_context
end

--- Find the longest suffix of delta_lines (after leading_echoes) that exactly
--- matches a contiguous run of lines in buffer_context. Returns the number of
--- echoed lines and the 0-based position in buffer_context where the echo starts.
--- @param delta_lines string[]
--- @param buffer_context string[]
--- @param leading_echoes integer
--- @return integer trailing_echoes
--- @return integer? echo_start_in_context_base0 -- position in buffer_context where the echo starts
local function find_trailing_echoes(delta_lines, buffer_context, leading_echoes)
    local delta_len = #delta_lines - leading_echoes
    if delta_len <= 0 then
        return 0, nil
    end

    -- Ignore trailing empty lines in the delta (e.g. from a trailing newline
    -- in the model's completion). They are noise and would prevent the echo
    -- detection from matching against the buffer context.
    while delta_len > 0 and delta_lines[leading_echoes + delta_len] == "" do
        delta_len = delta_len - 1
    end
    if delta_len <= 0 then
        return 0, nil
    end

    -- Try progressively shorter suffixes of the delta, from longest to shortest.
    for echo_len = delta_len, 1, -1 do
        local delta_start = leading_echoes + delta_len - echo_len + 1
        -- Try every contiguous run in buffer_context of the same length.
        for ctx_start = 1, #buffer_context - echo_len + 1 do
            local matches = true
            for i = 1, echo_len do
                if delta_lines[delta_start + i - 1] ~= buffer_context[ctx_start + i - 1] then
                    matches = false
                    break
                end
            end
            if matches then
                return echo_len, ctx_start - 1
            end
        end
    end
    return 0, nil
end

--- Trim delta lines that verbatim repeat the buffer lines immediately following
--- the anchor, both at the start (model echoed context before the change) and at
--- the end (model echoed context after the change). The middle lines are the
--- genuinely-new edit.
---
--- @param delta_lines string[]
--- @param buffer_lines string[]
--- @param anchor_buffer_line_base0 integer
--- @return string[] trimmed_delta
--- @return integer leading_echoes -- how many leading lines were echoes
--- @return integer trailing_echoes -- how many trailing lines were echoes
--- @return integer? echo_start_in_context_base0 -- where trailing echo starts in buffer context
function M.trim_repeated_context(delta_lines, buffer_lines, anchor_buffer_line_base0)
    local buffer_context = buffer_context_after_anchor(buffer_lines, anchor_buffer_line_base0)
    local trailing_context = buffer_context_for_trailing_echo(buffer_lines, anchor_buffer_line_base0)

    -- trim leading echoes (model repeated unchanged context before the change)
    local leading_echoes = 0
    while leading_echoes < #delta_lines and leading_echoes < #buffer_context
        and delta_lines[leading_echoes + 1] == buffer_context[leading_echoes + 1] do
        leading_echoes = leading_echoes + 1
    end

    -- trim trailing echoes: the model may repeat one or more unchanged buffer
    -- lines after its edit. Find the longest suffix of delta that matches a
    -- contiguous run in the buffer context (which may start at any position,
    -- e.g. when the model replaced a line and then echoed the line after it).
    local trailing_echoes, echo_start_in_context_base0 = find_trailing_echoes(
        delta_lines, trailing_context, leading_echoes)

    -- Also drop trailing empty lines from the delta (noise from a trailing
    -- newline in the completion), so they don't end up in the trimmed delta.
    local trimmed_end = #delta_lines
    while trimmed_end > leading_echoes and delta_lines[trimmed_end] == "" do
        trimmed_end = trimmed_end - 1
    end

    local trimmed = {}
    for i = leading_echoes + 1, trimmed_end - trailing_echoes do
        table.insert(trimmed, delta_lines[i])
    end
    return trimmed, leading_echoes, trailing_echoes, echo_start_in_context_base0
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

    local leading_echoes, trailing_echoes, echo_start_in_context_base0
    delta_lines, leading_echoes, trailing_echoes, echo_start_in_context_base0 =
        M.trim_repeated_context(delta_lines, buffer_lines, anchor_buffer_line_base0)

    local result = {
        anchor_line_base0 = anchor_buffer_line_base0,
        insertion_lines = delta_lines,
    }

    -- Determine where the edit begins in the buffer.
    -- When the anchor is the cursor line, the edit is at the cursor column
    -- (mid-line completion). Otherwise it begins after the anchor + leading
    -- echoes (i.e. where the change starts).
    local edit_start_line_base0
    local edit_start_col_base0
    if anchor_buffer_line_base0 == cursor_line_base0 then
        edit_start_line_base0 = anchor_buffer_line_base0
        edit_start_col_base0 = cursor_col_base0
    else
        edit_start_line_base0 = anchor_buffer_line_base0 + 1 + leading_echoes
        edit_start_col_base0 = 0
        if edit_start_line_base0 == cursor_line_base0 then
            edit_start_col_base0 = cursor_col_base0
        end
    end

    -- Determine whether the delta replaces existing lines or is a pure insert.
    -- The trailing echo tells us where the model's edit ends in the buffer.
    -- trailing_context starts at the anchor line (index 0 = anchor line).
    -- If the echo starts at trailing_context[1] (the anchor line), the model
    -- echoed the anchor after the change, so there is no replacement span
    -- (pure insertion).
    local replacement_happens = trailing_echoes > 0
        and echo_start_in_context_base0 ~= nil
        and echo_start_in_context_base0 > 0

    if replacement_happens then
        -- The replacement starts at edit_start and ends where the trailing
        -- echo begins in the buffer (echo_start_in_context_base0 is 0-based
        -- within trailing_context, which starts at the anchor line).
        local replace_end_line_base0 = anchor_buffer_line_base0 + echo_start_in_context_base0
        -- The replacement is line-wise: replace whole lines up to (but not
        -- including) the echoed line. The end column is 0 so the newline at
        -- the end of the last replaced line is preserved.
        result.replace_start_line_base0 = edit_start_line_base0
        result.replace_start_col_base0 = 0
        result.replace_end_line_base0 = replace_end_line_base0
        result.replace_end_col_base0 = 0
        -- The trailing echo extends from replace_end_line_base0 for
        -- trailing_echoes lines. Store the exclusive end so the display can
        -- also hide the echoed context (e.g. a trailing `end` line).
        result.trailing_echo_end_line_base0 = replace_end_line_base0 + trailing_echoes
        result.insertion_line_base0 = edit_start_line_base0
        result.insertion_col_base0 = 0
    else
        -- Pure insertion: insert at the edit start position.
        result.insertion_line_base0 = edit_start_line_base0
        result.insertion_col_base0 = edit_start_col_base0
    end

    return result
end

return M
