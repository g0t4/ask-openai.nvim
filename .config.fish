abbr ptw_apply_patch_wrapper 'ptw --clear lua/ask-openai/tools/inproc/apply_patch_wrapper_tests.py --  --capture=no --log-cli-level=INFO'
abbr ptw_chunking 'ptw --clear *_tests.py -- lsp/chunks/*.py --capture=no --log-cli-level=INFO'

abbr run_vite 'cd tools/chat_viewer_web; npm run dev'


# * E2E test abbreviations for ask-openai.nvim
#    Run with: type the abbr then tab to expand
abbr --position=anywhere --set-cursor e2e-pred "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-rewrite "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-agent "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-all "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\""
