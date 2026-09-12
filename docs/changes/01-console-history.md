# 01 — Console history

## The problem

Ask a question in the console, leave the page, and everything was gone. Turns
lived in React state and nowhere else, so the question, the reasoning and the
plan were lost together. Worse: a turn that was **not executed** has no run
behind it either, so there was nothing to find it under — and leaving the box
unticked is the commonest way the console is used.

## What was done

The thread moved to the gateway: `conversations` and `conversation_turns`. The
panel lists sessions in a sidebar; `localStorage` now holds only "which one was
open last".

A turn carries the sentence asked, the tool chosen, the reasoning, the command or
query it resolved to, the warnings, and the run reference when there is one.

## Why the output is not on the turn

`runRef` **points at** the run rather than copying it. Two copies of a result set
means two places to look when personal data has to be found or removed, and the
second is the one nobody remembers.

## Security: the output is sealed now

Query output sat in `run_targets` in the clear. Whatever a report returned —
accounts, e-mail addresses, national id numbers — was there.

It now goes through `RunOutputCipher` to mcp-cipher:

- Text and rows travel in **one envelope**, because neither can safely be derived
  from the other: one is what a person reads, the other is what a table is drawn
  from.
- **No plaintext fallback.** If sealing fails the output is not stored, and the
  row says so. Dropping the protection exactly when something is already wrong
  is making the worst decision at the worst moment.
- **Schema reads stay in the clear** — the planner reads them back, and there is
  nobody's data in a list of tables and columns.

## Warnings are kept too

A `warnings` column was added. A warning is worth more later than at the time:
"did that number count everything?" is asked a week afterwards, by which point
the live warning has scrolled away.

The warning shape later changed from `["text"]` to `[{code, detail}]`, and doing
that without migrating the old rows made `/api/v1/conversations` return 500 on
any page containing one. Migration `023-warning-shape.sql`.

## Verified by

`ConversationServiceTest` — what a recorded turn holds, that somebody else's
conversation is not found, that turns falling out of the window are folded into a
summary, and that a turn is never folded in twice.

`RunResultRecorderTest` — sealing, the absence of a plaintext fallback, and
schema reads staying readable.

`ConsoleHistory.test.tsx` — a turn that was only planned comes back, and the next
question lands in the conversation that is open.
