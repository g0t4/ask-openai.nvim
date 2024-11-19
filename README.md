# ask-openai.nvim

https://github.com/user-attachments/assets/aa03e773-dcef-4e8d-9c94-e341f4f3f7fc

Ask OpenAI for help in vim's command line!

New to using neovim? Need to learn the ropes a bit better? Use this as a crutch so you don't run away screaming and instead take the time to learn your way around. Use OpenAI's gpt-4o (et al) to recall that pesky command that evades recollection.

## Examples

```vim
:save all files<C-b>
" turns into:
:wall

:shut it down...  screw my work, I'm done with this POS<C-b>
" turns into:
:qa!

:what is the current filetype?<C-b>
:echo &filetype

:how do I wrap text<C-b>
:set wrap

:what key in normal mode copies 2 lines<C-b>
:normal 2yy

:test<C-b>
:echo "hello world"

```

Let me know if there are other ways you'd like to ask for help, beyond the command line. And no, I'm not talking about vscode.

## Installation

This works with any plugin manager. The plugin repo name `g0t4/ask-openai.nvim` is all you need to use this.

### Using lazy.nvim

```lua
{
    "g0t4/ask-openai.nvim",

    -- include one of the following:
    -- 1. set opts, empty = defaults
    opts = { },
    -- 2. call setup
    config = function()
        require("ask-openai").setup { }
    end,

    dependencies = { "nvim-lua/plenary.nvim" },
    -- must authenticate once with copilot.vim/lua before using the above copilot provider
    -- does not directly depend on github/copilot.vim

    event = { "CmdlineEnter" }, -- optional, for startup speed
    -- FYI most of the initial performance hit doesn't happen until the first use
}
```

### Using packer.nvim

```lua
use {
    "g0t4/ask-openai.nvim",
    config = function()
        require("ask-openai").setup { }
    end,
    requires = { "nvim-lua/plenary.nvim" },
    event = { "CmdlineEnter" }, -- optional
}
```

## Options

> 📌 **Tip:** check [config.lua](lua/ask-openai/config.lua) for all options

```lua
opts = {
    -- modify keymap
    keymaps = {
        -- disable:
        cmdline_ask = false,
        -- change:
        cmdline_ask = "<leader>a", -- default: <C-b>
    },

    provider = "copilot"
    -- "copilot" uses GitHub Copilot's API w/ your existing account
    -- "keychain" (macOS only) looks up the API Token with security command
    -- "keyless" - api key doesn't matter, i.e. ollama (by default assumes ollama's API endpoint)
    --   "ollama" is an alias for "keyless"
    -- function() ... end - see BYOK below
    -- "auto" will use the first available provider

    verbose = true, -- print verbose messages, i.e. which provider is used on first ask
}
```

### Using ollama

> ⚠️ ollama support is early, and I may change how it works, especially if people hve issues configuring it

```lua
opts = {
    provider = "keyless", -- or "ollama"
    model = "llama3.2-vision:11b", -- ollama list

    -- optional, if not default host:port
    api_url = "http://localhost:11434/api/chat", -- include endpoint /api/chat b/c keyless can be any openai compatible endpoint
}
```

### Using groq (or another OpenAI compatible endpoint)

This shows how to override api_url, or keychain service/account name, or both. Also, groq is insanely fast and FREE right now!

```lua
opts = {
    provider = "keychain",

    model = "llama-3.2-90b-text-preview",
    api_url = "https://api.groq.com/openai/v1/chat/completions",

    -- optional:
    keychain = {
        service = "groq",
        account = "ask",
    },
}
```

### BYOK - Environment Variables

```lua
opts = {
    provider = function()
        return os.getenv("OPENAI_API_KEY")
    end,
}
```

```bash
# FYI, test env var from keychain
export OPENAI_API_KEY=$(security find-generic-password -s openai -a ask -w )
```

### BYOK - macOS Keychain

```lua
opts = {
    provider = function()
        return require("ask-openai.config")
            .get_key_from_stdout("security find-generic-password -s openai -a ask -w")
    end,
}
```

```bash
# FYI, to set keychain password
security add-generic-password -a ask -s openai -w
# provide password when prompted
```

## TODOs

-   ad help docs (scaffold off of lua type annotations?)
-   add `checkhealth` support
