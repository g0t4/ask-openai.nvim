# echo fucker

abbr ptw_apply_patch_multi 'ptw --clear lua/ask-openai/tools/inproc/apply_patch_multi_tests.py --  --capture=no --log-cli-level=INFO'

function deactivate_local_config_fish
    # FYI would be cool to track new functions when this local config.fish file is sourced and auto remove those on deactivate
    functions --erase ptw_apply_patch_multi
end
