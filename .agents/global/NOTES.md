## verification/testing instructs

- FYI can apply these notes to any test tool, not just lua+nvim

Probably a bit of both global and repo instructions:
- General guidance per too: `/lua_nvim_global`?
- Project specific guidance: `/lua_nvim_repo`?
  (should include `/lua_nvim_global` so can be excluded if not relevant for a given repo)

per project could have entrypoints to test various subsets, should list prominent ones or make it obvious how to find them.
```examples.sh
nvim --headless -c "PlenaryBustedFile lua/ask-openai/frontends/context/prompt_parser.tests.lua" -c qa
```

consider:
- test file naming convention (organization too)
- test names/classes
- parameterizing test functions

PER REPO should have a `/verify_this_project` that specifically explains how to verify all subsystems!
  tests
  manual tests + expected output
  compiling code
  linting
  verification tools
    TODO build my own set of verifications that run when loaded, in fact this is the loader more or less... if loads => good to go!

