from wes_local_config import local_abbr
#
cd_repo_root = "cd ~/repos/github/g0t4/ask-openai.nvim"
cd_rag = f"{cd_repo_root}/lua/ask-openai/rag"
local_abbr("ptw_apply_patch_wrapper", f"{cd_repo_root}; ptw --clear lua/ask-openai/tools/inproc/apply_patch_wrapper_tests.py --  --capture=no --log-cli-level=INFO")
local_abbr("ptw_chunking", f"{cd_rag}; ptw --clear *_tests.py -- chunks/*.py --capture=no --log-cli-level=INFO")
cd_chat_viewer_web = f"{cd_repo_root}/tools/chat_viewer_web"
local_abbr("run_vite", f"{cd_chat_viewer_web}; npm run dev")

# * E2E test abbreviations for ask-openai.nvim
local_abbr("e2e-pred", "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" -c quit!", position="anywhere")
local_abbr("e2e-rewrite", "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\" -c quit!", position="anywhere")
local_abbr("e2e-agent", "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" -c quit!", position="anywhere")
local_abbr("e2e-all", "nvim --headless -c \"PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/predictions/e2e.tests.lua\" && nvim --headless -c \"PlenaryBustedFile lua/ask-openai/rewrites/e2e.tests.lua\"", position="anywhere")
