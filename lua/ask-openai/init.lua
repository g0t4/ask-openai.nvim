local M = {}

function M.setup(opts)
    vim.notify("setup called")


    -- TODO modify this to use github copilot subscription/api using chat model and see how it performs vs openai gpt4o (FYI windows terminal chat w/ copilot was clearly inferior vs gpt4o but ... win term chat might have been using gpt3.5 or smth else, just FYI"
    -- TODO port to lua
    -- TODO remove python dependency too
    vim.cmd([[

        function! TrimNullCharacters(input)
            " Replace null characters (\x00) with an empty string
            " was getting ^@ at end of command output w/ system call (below)
            return substitute(a:input, '\%x00', '', 'g')
        endfunction

        function! AskOpenAI()

            let l:cmdline = getcmdline()

            " todo this prompt here should be moved into vim.py script and combined with other system message instructs? specifically the don't include leading :? or should I allow leading: b/c it still works to have it
            let l:STDIN_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' . l:cmdline

            " PRN use env var for DOTFILES_DIR, fish shell has WES_DOTFILES variable that can be used too
            let l:DOTFILES_DIR = '~/repos/wes-config/wes-bootstrap/subs/dotfiles'
            let l:py = l:DOTFILES_DIR . '/.venv/bin/python3'
            let l:vim_py = l:DOTFILES_DIR . '/zsh/universals/3-last/ask-openai/vim.py'
            let l:command_ask = l:py . ' ' . l:vim_py

            let l:result = system(l:command_ask, l:STDIN_text)

            return TrimNullCharacters(l:result)

        endfunction

        " Map a key combination to the custom command in command-line mode
        cmap <C-b> <C-\>eAskOpenAI()<CR>

    ]])
end

return M
