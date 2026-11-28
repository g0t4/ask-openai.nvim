# Feature: Pair Refactoring (two-way, human-in-the-loop)

## Problem statement

Refactoring large codebases today means reading in the diff, either scanning a wall of
change at the end of a session, or running `git diff` and losing focus in between.
We pair with an AI agent (like me) instead of letting it do a long unattended pass,
and we want that pairing to feel native to the editor — small steps, in-flow review,
with a git-based safety net.

## Goals

- Small steps with pause for human review.
- Human review UX is mostly `👍` or `👎`, followed by instructions on what to do next
  (or what to do instead).
- Commit every small approved change (not just at the end).
- Rollback is a first-class operation: any point, `git revert`, pause for human
  confirmation, then head down the corrected path.
- Review is surfaced *inside* the editor at the same spot the human was looking at —
  not a separate git diff invocation (focus preservation).
- The human's cursor position is a cheap, meaningful signal (a lightweight proxy for
  code selection, similar to the current FIM/Scoping flows).

## Differences from existing tools

### Agent harness (agents/)
Largely intended for the human to be *out of the loop*. Less need for review
("yolo" mode). Pair-refactoring explicitly keeps the human in the loop — small
diffs, frequent review, "pause → proceed" — so it is a different UX, not a mode of
the existing agent flow.

### FIM / Edit Predictions
Very narrow, single-cursor-line-scoped — not amenable to human steering. Pair-refactoring
is a broad, interactive session over many chunks of code; cursor is just a signal,
not the center of gravity.

### AskRewrite
Select a block of code → make a change to it. Pair-refactoring does not require the
human to select code at all; human selects direction via conversation, not selection.

## Two-way voice

Two-way voice (full-duplex speech) is likely the key enabler for this — talking to
the agent while it works means review flows naturally instead of through a
mechanical turn boundary.

## Session history as the primary signal

The conversation/session history is the main context signal for the next step.
Cursor position supplements it lightly.

## Sketch of the loop

1. Agent proposes a small change (single function, single file, single class).
2. Agent commits it locally (small, focused commit).
3. Agent pauses and asks for review: `👍` / `👎 something else`.
4. Human reviews (in-editor diff view of the commit, ideally at the same position
   they were reading), responds with 👍 or a correction.
5. On 👎 or "change direction": human re-labels instructions; agent reverts (with
   pause to confirm the revert matches intent) and starts a new small step.
6. Repeat until the session is done.

## Ideas worth exploring

### Tooling / UX

- **Diff view in the editor**: a neovim diffview / gitsigns-style view showing the
  before/after of the last approved commit as two panes (left=old, right=new),
  keeping focus and position stable.
- **Inline diff preview**: if the changed lines are in the human's viewport, show
  the hunk as an overlay / inline diff rather than a full diff pane.
- **Auto-advance while reviewing**: after human says "👍", immediately jump to the
  next small change instead of forcing the human to re-navigate.
- **Cursor position as a soft anchor**: use cursor/selection to bias what the agent
  should touch next (and to preview which hunks the human is looking at). Conversation
  history is still the primary signal.
- **Session history retrieval**: maybe a view into recent steps/approves/rollbacks
  in the session for context-gathering and direction changes.

### Git workflow

- **Commit per small change**, not at the end. Small commits are fast to review here.
- **Commit right before review** (i.e. the approval is tied to a concrete, small diff).
- **Rollback pause**: after reverting one or more commits, pause and confirm with the
  human that both parties are on the same page before proceeding.
- Keep hooks in mind: edits show in buffer; the commits should remain small and
  focused for readability.

### UX of the review gate

- Default review is `👍` / `👎`. Corrections are natural-language instructions
  ("do the reverse of that" / "expand this into two commits" / "skip this step")
  rather than a picker.
- The pause is *before* the commit is applied — agent shows the planned change
  (or commits it in a non-pushed state) and waits.
- `git revert` as the rollback mechanism: keeps history legible and is trivially
  testable.

## Non-goals / open questions

- How much of this can live in plain neovim + git (diffview, gitsigns, minimal
  harness) vs. needing bespoke tooling to interoperate with agent output.
- How the voice loop is implemented (tmux/speak-to-hear, or terminal-multiplexing
  voice UX) — separate design effort.
- How to make the overlay stable (no flicker / no jarring refresh) and how to keep
  cursor position from fighting the overlay.
- Whether streaming writes should happen before the review gate, or only after an
  explicit "go".
