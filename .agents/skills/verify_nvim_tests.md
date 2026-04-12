
TODO add test guidance around running plenary tests with neovim headless
- probably should make this per repo (project) and recursively include a global set of explanations around generally how to do it!

per project could have entrypoints to test various subsets:
```examples.sh
nvim --headless -c "PlenaryBustedFile lua/ask-openai/predictions/context/prompts.tests.lua" -c qa
```

PER REPO should honestly have a verify_this_project that specifically explains how to verify all subsystems!
  tests
  manual tests + expected output
  compiling code
  linting
  verification tools (i.e. skills-verify or w/e the name is)


