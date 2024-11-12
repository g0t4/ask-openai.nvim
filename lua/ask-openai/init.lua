local M = {}

function M.setup(opts)
    require("ask-openai.new") -- source new funcs TODO how do I want this to work?

    require("ask-openai.config").set_user_opts(opts)

    -- TODO modify this to use github copilot subscription/api using chat model and see how it performs vs openai gpt4o (FYI windows terminal chat w/ copilot was clearly inferior vs gpt4o but ... win term chat might have been using gpt3.5 or smth else, just FYI"

    function trim_null_characters(input)
        -- Replace null characters (\x00) with an empty string
        -- was getting ^@ at end of command output w/ system call (below)
        if input == nil then
            return ""
        end
        return input:gsub("%z", "")
    end

    function ask_openai()
        local cmdline = vim.fn.getcmdline()

        local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
            cmdline

        local result = get_vim_command_suggestion(stdin_text)

        return trim_null_characters(result)
    end

    vim.cmd [[
        function! AskOpenAI()
            " just a wrapper so the CLI shows "AskOpenAI" instead of "luaeval('ask_openai()')"
            return luaeval('ask_openai()')
            " also, FYI, luaeval and the nature of a cmap modifying cmdline means there really is no way to present errors short of putting them into the command line, which is fine and how I do it in my CLI equivalents of this
            "   only issue w/ putting into cmdline is no UNDO AFAIK for going back to what you had typed... unlike how I can do that in fish shell and just ctrl+z to undo the error message, but error messages are gonna be pretty rare so NBD for now
        endfunction
    ]]

    -- [e]valuate expression AskOpenAI() in command-line mode
    -- DO NOT SET silent=true, messes up putting result into cmdline
    vim.api.nvim_set_keymap('c', '<C-b>', '<C-\\>eAskOpenAI()<CR>', { noremap = true, })

    -- setup_on_the_fly_hints()
end

function setup_on_the_fly_hints()
    if not require("ask-openai.config").user_opts.on_the_fly_hints then
        return
        -- TODO make runtime TOGGLE
    end

    -- TODO setup some sort of integration testing to figure out what keys map to what, don't keep testing this manually
    local last_keys = ""

    vim.on_key(function(key_after_mapping, key_before_mapping)
        local mode = vim.fn.mode()

        -- what modes to exit on? TODO tracmode with key? is this the mode before or after the key press?
        -- if k == "" or mode == "c" or mode == "R" then
        --     return
        -- end
        --

        local key = vim.fn.keytrans(key_before_mapping)
	
	-- ! TODO log messages to a file and have it open in a split window, so much to log I need a file

        -- last_keys = last_keys .. "\n" .. key
        last_keys = key .. "\n" .. last_keys

        -- for Ctrl keys:
        -- print(key)
        -- print(type(key))
        -- FYI if don't pass 1, true) then it reports false matches sometimes
        --   lua print(string.find("<Esc>","^C-")) => 1 0
        --   lua print(string.find("<Esc>","^C-",1,false)) => 1 0
        --   lua print(string.find("<Esc>","^C-",1,true)) => nil
        --
        -- so, 1 0 is invalid b/c 0 < 1 plus lua is 1-indexed so 0 alone isn't valid anyways
        --  IIRC 1 1 sometimes returned too in bogus match
        --  :lua print(string.find("<Esc>","<C-")) => 1 1
        --  TLDR => pass pattern=true to avoid headache, don't try string match?
        --
        local match = string.find(key, "<C-", 1, true)
        -- print(key .. " pressed, before: " .. key_before_mapping .. ", after: " .. key_after_mapping)
        if match then
            -- vim.notify(key .. " pressed\nbefore: " .. key_before_mapping .. "\nafter: " .. key_after_mapping)
            return
        end

        -- TODO when to clear last_keys? maybe after get suggestion?
        -- ! FYI I am not sure I wanna ask on every keypress, just means might have some delayed suggestions?
        --   MAYBE it would be better to just create more hints ihn hardtime? and be done with it?

        -- TODO so we have key_after/before_mapping, plus there is keytrans?
        --   what do I use or does it even matter, just ask openai with after? and one per line?
        --
    end)
end

return M
