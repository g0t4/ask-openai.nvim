Find one seam in the code under my cursor or in my selection. Use the surrounding code and my recent edits to infer which responsibility I’m trying to move. Preserve observable behavior.

Show me the proposed cut at the call site. Pick the smallest excerpt that lets me judge it. Often the name, arguments, and return value are enough. Include the other side of the boundary when ownership or side effects would otherwise be hard to see.

Let me steer before applying the edit. If I say “seam” again, show a different plausible cut. If I nudge the boundary, revise the preview. Once I accept, make the edit, update the affected callers, and verify the behavior.
