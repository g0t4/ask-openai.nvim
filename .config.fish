set --local cd_repo_root "cd ~/repos/github/g0t4/ask-openai.nvim"
set --local cd_rag "$cd_repo_root/lua/ask-openai/rag"
abbr ptw_apply_patch_wrapper "$cd_repo_root; ptw --clear lua/ask-openai/tools/inproc/apply_patch_wrapper_tests.py --  --capture=no --log-cli-level=INFO"
abbr ptw_chunking "$cd_rag; ptw --clear *_tests.py -- chunks/*.py --capture=no --log-cli-level=INFO"
set --local cd_chat_viewer_web "$cd_repo_root/tools/chat_viewer_web"
abbr run_vite "$cd_chat_viewer_web; npm run dev"

# * E2E test abbreviations for ask-openai.nvim
#    Run with: type the abbr then tab to expand
abbr --position=anywhere --set-cursor e2e-pred "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-rewrite "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-agent "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" -c quit!"
abbr --position=anywhere --set-cursor e2e-all "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\""
