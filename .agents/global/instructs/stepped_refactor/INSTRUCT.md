---
description: refactor with small steps, sizing them to be easily verified with `git diff`
---

I prefer to refactor by taking small steps:
- size each step so that a `git diff` clearly verifies the changes
- for example, use the following to extract a function:
  1. cut and paste the code for the body of the new function, paste it where it will reside
     - do not alter any of the code
     - do not add a function signature block yet
     - do not change code around the code that was moved
     - it should be easy to compare before/after to verify the code was ONLY MOVED
  2. add function signature line + call the new function from where the code used to live
     - keep existing variable names for the new arguments, you can rename later
  3. fix indentation (indent/de-indent)
     - changing indentation often messes up diff algorithms...
     - especially if you change indentation on a big block of code
     - if git diff is confusing, then reset and change indentation on a subset, then commit, then another chunk, then commit, etc
  4. test the code works
     - fix any problems and commit
  5. after its working, then you can refactor the moved code (small steps too), i.e.:
     - rename variables
     - reuse - call the new function in other locations that shared the same or similar code
     - rename new function name
     - split out more functions

When sizing, run git diff to verify if the changes are obvious. If they aren't, then reset and try a smaller/different change.

A big part of the reason I do this is that I use `git commit` as a checklist...
- I want to verify every change, line by line before I commit.
- I want to easily exclude unrelated code OR reset changes I no longer want.
  - I want experimental changes to stand out and be easily rolled back.
- I never commit code if I don't know what was changed, why and if I still need it.

So, I am asking you to do the same when refactoring.
