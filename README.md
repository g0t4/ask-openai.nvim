# ask-openai.nvim

Ask OpenAI for help in vim's command line!

New to using neovim? Need to learn the ropes a bit better? Use this as a crutch so you don't run away screaming and instead take the time to learn your way around. Use OpenAI's gpt-4o (et al) to recall that pesky command that evades recollection.

## Examples

```vim
:save all files<Ctrl-b>
" turns into:
:wall

:shut it down, now...  I don't care if I lose my work, I'm done with this POS<Ctrl-b>
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

Using lazy.nvim:

```lua
{
    "g0t4/ask-openai.nvim",
    -- TODO lazy on cmdline enter?

    -- for options, include one of the following (not both):
    -- 1. set opts
    opts = {
        -- providers are used to access OpenAI's API
        -- "copilot" uses GitHub Copilot's API w/ your existing account
        -- "keychain" (macOS only) looks up the API Token with security command (keychains)
        -- WIP - password less (i.e. ollama)
        provider = "copilot", -- or, "auto", "keychain" (see config.lua for details)
        -- verbose = true,
    },
    -- 2. call setup yourself and pass opts
    config = function()
        -- this sets up the keybinding for <Ctrl-b>:
        require("ask-openai").setup {
            -- same options as above, i.e.:
            provider = "copilot",
        }
    end,

    dependencies = {
        -- FYI you do not need github/copilot.vim to load before ask-openai, just need to authenticate (one time) w/ copilot.vim/lua before using the copilot provider here
        "nvim-lua/plenary.nvim",
    },
}
```

## TODOs

-   add help docs (scaffold off of lua type annotations?)
-   add `checkhealth` support
-   TODO ADD ollama and other opeani complient (no auth token needed) provider
-   TODO MAKE keychain provider configuable on URL, actually just make URL configurable regardless of provider?
