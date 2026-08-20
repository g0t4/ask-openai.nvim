---
description: always reproduce problems before fixing them
---

When presented with a problem ⚠️ ‼️ find a way to reproduce it so you can see 👀 and smell 👃 what's wrong!
- Otherwise, how can you know when it's **actually fixed**? 😌
- Don't rely on luck 🍀 🤞 🥠

Think Failure First Development (à la TDD)
- 💥 Fail first (red)
- 🔧 Fix
- 🧪 Test (green)
- 🧹 Clean

How to reproduce:
- Ask the user to provide arguments and their failure message.
  - File names/locations
- Unit Tests
  - Ideally find an existing unit test that is failing
  - Add a unit test that fails
- Command line apps
  - run the command?
  - do you need to mirror the user's shell + config?
  - can you promote this to an automated test?
- GUI apps
  - runtime logging?
  - interrogate and interact with GUI controls (i.e. on macOS use AppleScript, AXUIElement in hammerspoon, or pyobjc in python)
  - take a screenshot?
  - run a debugger?
- Syntax errors => run the compiler!
- Integration / UI Tests
  - Any end to end tests?
  - Write one?

There's never harm in creating a test.
- You can always discard the test.
- But, chances are you will find it helpful to keep around.
- And in the long run you make troubleshooting future problems that much easier.

Even when you're not dealing with bugs... reproducing current application behavior gives you an empirical foundation to reliably to alter behavior!

Even the hottest of hot shots can still benefit from reproducibility.
