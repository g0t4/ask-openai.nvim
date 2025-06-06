# ask-openai.nvim

https://github.com/user-attachments/assets/aa03e773-dcef-4e8d-9c94-e341f4f3f7fc

Ask OpenAI for help in vim's command line!

New to using neovim? Need to learn the ropes a bit better? Use this as a crutch so you don't run away screaming and instead take the time to learn your way around. Use OpenAI's gpt-4o (et al) to recall that pesky command that evades recollection.

## Examples

```vim
:save all files<C-b>
" turns into:
:wall

:run ls command and copy output into buffer<C-b>
" turns into:
:r !ls

:shut it down... screw my work, I'm done with this POS<C-b>
:qa!

:insert a UUID<C-b>
:r!uuidgen

:what is the current filetype?<C-b>
:echo &filetype

:how do I wrap text<C-b>
:set wrap

:what key in normal mode copies 2 lines<C-b>
:normal 2yy

:what clear search highlights<C-b>
:nohlsearch

:test<C-b>
:echo "hello world"
" don't forget, there's often more than one way to do something

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

    event = { "CmdlineEnter" }, -- optional, for startup speed
    -- FYI most of the initial performance hit doesn't happen until the first use
}
```

### Using packer.nvim

```lua
use {
    "g0t4/ask-openai.nvim",
    config = function()
        require("ask-openai").setup { } -- empty == default options
    end,
    requires = { "nvim-lua/plenary.nvim" },
    event = { "CmdlineEnter" }, -- optional
}
```

## Options

> 📌 **Tip:** check [config.lua](lua/ask-openai/config.lua) for all options

### Using GitHub Copilot (default)

If you pass an empty opts table `{ }` then copilot will be used.

```lua
opts = {
    provider = "copilot", -- default
}

-- must authenticate once with copilot.vim/lua before ask-openai will work
-- does not directly depend on github/copilot.vim plugin
```

### Using ollama

> ⚠️ ollama support is early, and I may change how it works, especially if people have issues

```lua
opts = {
    provider = "keyless",
    model = "llama3.2-vision:11b",
    use_api_ollama = true, -- use ollama default, OR:
    -- api_url = "http://localhost:11434/api/chat" -- override default for ollama
}
```

### Using groq + macOS Keychain

> 💨 groq is insanely fast and FREE right now!

```lua
opts = {
    provider = function()
        -- use any logic you want, this is just an example:
        return require("ask-openai.config")
            .get_key_from_stdout("security find-generic-password -s groq -a ask -w" )
    end,

    model = "llama-3.2-90b-text-preview",
    use_api_groq = true,
}
```

```bash
# FYI, to set keychain password
security add-generic-password -a ask -s groq -w
# provide password when prompted
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

### Customizing the keymap

```lua
opts = {
    keymaps = {
        cmdline_ask = "<C-b>", -- default
        -- or:
        cmdline_ask = false, -- disable it, see init.lua how it's set
    },
}
```

## Troubleshooting

Enable verbose logging:

```lua
opts = {
    verbose = true,
}
```

Then, make a request, then check messages for verbose logs:

```vim
:messages
```

Don't forget health checks:

```vim
:checkhealth ask-openai
" FYI verbose mode adds extra health check info
```

And help:

```vim
:help ask-openai<Tab>
" Lazy plugin manager turns this README.md into helptags. If your using a different plugin manager, you might not see these help docs.
```

## TODOs
- ollama has /v1/chat/completions too (see my single.py in fish ask openai), use that instead of that custom thing I did
