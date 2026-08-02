local M = {}

--- Color text based on token probability.
--- Higher probability = less visible color (prob=1.0 has no color).
--- Lower probability = more intense red color.
---@param text string The text to color
---@param prob number|nil Token probability (0-1), nil means no coloring
---@return string Colored text with ANSI escape codes
local function color_by_probability(text, prob)
    -- No probability data available, return plain text
    if prob == nil then
        return text
    end

    -- Perfect confidence = no color
    if prob >= 1.0 then
        return text
    end

    -- Calculate intensity (0 = no color, 1 = full red)
    local intensity = 1.0 - prob
    -- Clamp to [0, 1]
    intensity = math.max(0, math.min(1, intensity))

    -- Color gradient: green (high confidence) -> yellow -> red (low confidence)
    -- At prob=1.0: no color (handled above)
    -- At prob=0.9-1.0: very subtle green tint
    -- At prob=0.7-0.9: yellow-green
    -- At prob=0.5-0.7: yellow-orange
    -- At prob<0.5: orange-red
    -- At prob~0.0: bright red

    local r, g, b
    if intensity < 0.33 then
        -- High confidence: green tint (low intensity)
        -- intensity 0-0.33 maps to rgb(200, 255, 200) -> rgb(255, 255, 0)
        local t = intensity / 0.33
        r = math.floor(200 + t * 55)
        g = 255
        b = math.floor(200 - t * 200)
    elseif intensity < 0.66 then
        -- Medium confidence: yellow to orange
        -- intensity 0.33-0.66 maps to rgb(255, 255, 0) -> rgb(255, 165, 0)
        local t = (intensity - 0.33) / 0.33
        r = 255
        g = math.floor(255 - t * 90)
        b = 0
    else
        -- Low confidence: orange to red
        -- intensity 0.66-1.0 maps to rgb(255, 165, 0) -> rgb(255, 0, 0)
        local t = (intensity - 0.66) / 0.34
        r = 255
        g = math.floor(165 * (1 - t))
        b = 0
    end
    return ansi.rgb(text, r, g, b)
end

---@param prob number|nil
---@return string probability display
local function display_probability(prob)
    -- toggle on/off instead of comment out code
    local show_probabilities = true
    -- local show_probabilities = false

    if show_probabilities then
        -- FYI keep this nested condition for readability
        local gray = 100
        if prob == nil then
            return ansi.rgb(ansi.italic("(?)"), gray, gray, gray)
        elseif prob < 1.0 then
            return ansi.rgb(ansi.italic(string.format("(%.2f)", prob)), gray, gray, gray)
        end
    end

    return ""
end

--- Format a single token with its probability for logging.
---@param token string text
---@param prob number|nil Token probability (0-1)
---@return string Formatted string with probability indicator
local function format_token_with_prob(token, prob)
    local colored_text = color_by_probability(token, prob)
    return colored_text .. display_probability(prob)
end


---@param sse_fields_list SseFieldsResult[]
---@return { reasoning: string, content: string }
function M.probability_colored_outputs(sse_fields_list)
    local reasoning_parts = {}
    local content_parts = {}

    local sse_count = #sse_fields_list

    for sse_index_base0 = 0, sse_count - 1 do
        local sse_fields = sse_fields_list[sse_index_base0 + 1]

        local is_reasoning = sse_fields.reasoning_content and sse_fields.reasoning_content ~= ""
        if is_reasoning then
            table.insert(reasoning_parts, format_token_with_prob(sse_fields.reasoning_content, sse_fields.prob))
        end

        local is_content = sse_fields.content and sse_fields.content ~= ""
        if is_content then
            table.insert(content_parts, format_token_with_prob(sse_fields.content, sse_fields.prob))
        end
    end

    return {
        -- FYI do not join w/ a separator, the token has all the text
        reasoning = table.concat(reasoning_parts),
        content = table.concat(content_parts),
    }
end

return M
