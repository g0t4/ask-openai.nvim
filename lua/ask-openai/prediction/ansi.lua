local M = {}

local color_keys = {
    -- reset
    reset     = 0,

    -- misc
    bright    = 1,
    dim       = 2,
    underline = 4,
    blink     = 5,
    reverse   = 7,
    hidden    = 8,

    -- foreground colors
    black     = 30,
    red       = 31,
    green     = 32,
    yellow    = 33,
    blue      = 34,
    magenta   = 35,
    cyan      = 36,
    white     = 37,

    -- background colors
    blackbg   = 40,
    redbg     = 41,
    greenbg   = 42,
    yellowbg  = 43,
    bluebg    = 44,
    magentabg = 45,
    cyanbg    = 46,
    whitebg   = 47

    -- 3 and 4 bit color:
    --   https://en.wikipedia.org/wiki/ANSI_escape_code#3-bit_and_4-bit
}

-- TODO rewrite this to cover all colors... and be reusable.
-- Try using your new AI tools to do this (zed predicts too)

-- print("\27[31mThis is red text\27[0m")
function M.black(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.black .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.cyan(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.cyan .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.red_bold(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    local bold_text =
        "\27[" .. color_keys.bright .. ";" .. color_keys.red .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
    return bold_text
end

function M.red(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.red .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.blue(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.blue .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.magenta(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.magenta .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.green(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.green .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.yellow_bold(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    local bold_text =
        "\27[" .. color_keys.bright .. ";" .. color_keys.yellow .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
    return bold_text
end

function M.yellow(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.yellow .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

-- TODO later you can cleanup duplication

function M.white_bold(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    local bold_text =
        "\27[" .. color_keys.bright .. ";" .. color_keys.white .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
    return bold_text
end

function M.white(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.white .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.black_bg(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.blackbg .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.red_bg(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.redbg .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.blue_bg(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.bluebg .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

function M.underline(text, options)
    options = options or {}
    options.color = options.color or true -- default is true
    if not options.color then
        return text
    end
    return "\27[" .. color_keys.underline .. "m" .. text .. "\27[" .. color_keys.reset .. "m"
end

return M
