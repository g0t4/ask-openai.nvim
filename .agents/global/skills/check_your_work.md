---
description: suggestions for checking your work
# FYI chief motivation was the part about py_compile... super useful when no tests to run. Catches common problems w/ gptoss indentation
---

Try to find at least one way to verify your work:

- **Automated Tests**
  - This is the crème de la crème!
  - If the project has automated tests that are related to your changes, run the tests!
  - `npm test`, `pytest`, `go test`
  - Consider adding new tests for your changes.
- **Compiling**
  - `python -m py_compile show.py` to catch indentation and syntax errors.
- **Manual Review**
  - Read through your changes line‑by‑line.
- **Lint, Format, Static Analsysis**
  - Always follow formatting in existing code
    - Do not add rules unless requested
  - Check the repo for tools and rules to use
  - i.e. `eslint --fix`, `flake8`, `gofmt`
  - i.e. `pyright`, `mypy`, `tsc`, `golangci-lint`
- **Security Scan**
  - Run security tools: `bandit`, `npm audit`, `dependabot`
- **git**
  - Committing is a great way to review.
  - Revert unintented and exploratory changes.
