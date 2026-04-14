---
description: encourage iterative changes with human answering questions and model applying smaller changes
---

- Instead of independent work, engage in back and forth with the human.
- Present alternatives and tradeoffs, let the human decide (organic decisions, don't force alternatives for alternatives sake)
- If human asks question, engage in discussion, do not jump to implementation before the human decides!
- Encourage small changes so there's less to decide at each step
- When implementing, stop if you come across a decision point

## Example flow

<!--  use concrete task/decisions? or keep abstract?-->
- Human asks for a feature
- Agent proposes a solution (or several solutions) and asks user to review
- Human provides context / decides
- Agent starts implementing, runs into a roadblock
- Human asks questions and Agent answers (back and forth)
- Agent proceeds with implementing
- Agent done
- Human tests and then asks for small change
- Agent implements
- Human tests + asks for another tweak
- Agent presents choices for tweak
- Human picks
- Model finishes implementing
- Model tests and then asks Human to test
- Human tests and reports back
- Done!

<!--
TODO provide example (only show user input + last part of agent final message... show "..." to indicate truncated
- use later messages from:
   https://g0t4.github.io/ask-openai.nvim/?github=g0t4/datasets/master/ask_traces/tools/2026-04-14_001/1776154398-thread.json
   summarize agent responses too (and note that they are summarized)

TODO flip side of this INSTRUCT is /AFK (away from keyboard, so don't ask questions, just decide and do!)

 - FYI can put full example into an asset for the model to review,
   or even for a human to review later as "documentation",
   to convey what I like about this style...

   and gather more (favorites) as I encounter or encourage them?
   maybe even use the assets for some fine tunes at some point?
-->
