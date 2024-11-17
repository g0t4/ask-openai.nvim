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

:what key in normal mode copies 2 lines<Ctrl-b>
:normal yy
```

Let me know if there are other ways you'd like to ask for help, beyond the command line. And no, I'm not talking about vscode.

## Installation

Using lazy.nvim:

```lua
{
    "g0t4/ask-openai.nvim",
    opts = {
        provider = "auto",
        verbose = true,
    },
    config = function()
        -- this sets up the keybinding for <Ctrl-b>:
        require("ask-openai").setup()
    end,
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
}
```

## TODOs

- add help docs (scaffold off of lua type annotations?)
- add `checkhealth` support
