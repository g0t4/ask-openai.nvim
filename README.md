# ask-openai.nvim

Ask OpenAI for help in vim's command line!

New to using neovim? Need to learn the ropes a bit better? Use this as a crutch so you don't run away screaming and instead take the time to learn your way around. Use OpenAI's gpt-4o (et al) to recall that pesky command that evades recollection.

## Examples

```vim
:save all files<Ctrl-b>
" turns into:
:wall

:shut it down...  screw my work, I'm done with this POS<Ctrl-b>
:qa

:what is the current filetype?<Ctrl-b>
:echo &filetype

:how do I wrap text
:help textwidth

:what key in normal mode copies 2 lines<Ctrl-b>
:normal yy

:test
:echo "hello world"

```

Let me know if there are other ways you'd like to ask for help, beyond the command line. And no, I'm not talking about vscode.

## Installation

### Using lazy.nvim:

```lua
{
    "g0t4/ask-openai.nvim",
    -- TODO lazy on cmdline enter?

    -- include one of the following:
    -- 1. set opts
    opts = {
        -- see Options section below
    },
    -- 2. call setup
    config = function()
        require("ask-openai").setup {
            -- see Options section below
        }
    end,

    dependencies = {
        -- FYI you do not need github/copilot.vim to load before ask-openai, just need to authenticate (one time) w/ copilot.vim/lua before using the copilot provider here
        "nvim-lua/plenary.nvim",
    },
}
```

## Options

> 📌 **Tip:** check [config.lua](lua/ask-openai/config.lua) for all options

```lua
{
    -- modify keymap
    keymaps = {
        -- disable:
        cmdline_ask = false,
        -- change:
        cmdline_ask = "<leader>a",
    },

    provider = "copilot"
    -- "copilot" uses GitHub Copilot's API w/ your existing account
    -- "keychain" (macOS only) looks up the API Token with security command
    -- "keyless" - api key doesn't matter, i.e. ollama (by default assumes ollama's API endpoint)
    -- "auto" will use the first available provider

    verbose = true, -- print verbose messages, i.e. which provider is used on first ask
}
```

### Using ollama

> ⚠️ - ollama support is early, and I may change how it works, especially if people hve issues configuring it

```lua
{
    provider = "keyless",
    model = "llama3.2-vision:11b", -- ollama list

    -- optional, if not default host:port
    api_url = "http://localhost:11434/api/chat", -- include endpoint /api/chat b/c keyless can be any openai compatible endpoint
}
```

## TODOs

-   ad help docs (scaffold off of lua type annotations?)
-   add `checkhealth` support
