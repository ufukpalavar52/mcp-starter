# 16 — Approving a particular command

[06](06-approval.md) made approval real: a step the loop wrote is held, and a person says
yes. This file is about the two halves of that which were still missing — being able to say
**no**, and the approval actually running **the command that was shown**.

## Half a question

The card had one button. A screen that can only be agreed with is not asking anything; it is
waiting for somebody to give in — and the command above it is usually a delete.

There is now a Cancel beside it, and `POST /api/v1/tools/steps/{turnId}/decline`.

The turn is marked `declined`, not `rejected`. `rejected` already means something here: the
guardrails refused the command. This command was fine — a person looked at it and said no.
Different fact, different word, and a history that used one word for both would be unable to
answer "how often do the guardrails catch something?"

The goal stops offering the action, too. Turning a step down is a decision about the goal,
not "ask me again in a minute".

Ownership is checked exactly as approval is: the turn id comes from a browser, and a browser
may name any number at all.

## Approving did nothing, quietly

> "approve'a basıyorum ve dönüyor tekrar eski haline geliyor"

Approving **re-plans** rather than replays. That is deliberate: what was stored is a
sentence and the command it resolved to ten minutes ago, and running that on trust would be
the one path into the executor that skipped every check.

But the only thing going into the re-plan was the turn's sentence. A step the loop wrote
carries neither of the two things that make it what it is:

| What the plan needed | What the sentence has |
|---|---|
| the value — `id: 59` | nothing; the sentence is *"Processing the first user found…"* |
| the action — delete, of four | nothing; the choice is made afresh every time |

So both were guessed again. The id came back different, or the listing action was chosen
instead of the delete. Either way the re-planned command did not match the one that had been
shown, `expect` stopped the dispatch, and the card fell back to waiting.

**Nothing wrong ever ran.** The guard did its job. But it gave no account of itself, and
from the outside approve looked like a button that did nothing.

## Remembering instead of re-deriving

Two nullable columns, `025-turn-arguments.sql` and `026-turn-action.sql` in the gateway's
changelog:

```sql
ALTER TABLE conversation_turns ADD COLUMN arguments jsonb;   -- {"id": "59"}
ALTER TABLE conversation_turns ADD COLUMN action_id bigint;  -- 76
```

Both are read off the plan result rather than off what the caller passed in: a value the
loop read out of an answer and one routing found in a typed sentence are the same fact by
the time a plan exists, and the plan is the thing being approved. The action kept is the one
that resolved to something — an action the plan set aside carries no command.

Approving then re-plans from those. Same guardrails, same values, same action, same command.

```
onay öncesi : [59, 69, 86, 97]
approve 277 → DELETE /api/users/59  → queued
onay sonrası: [69, 86, 97]
```

and the loop carried on: it re-read the list and proposed `DELETE /api/users/69`, held.

## One at a time, on purpose

Four Yigits are four approvals. The loop proposes one step, waits for the answer, and
decides the next from it. A batch approval would give back exactly the assurance that
approving one command at a time is there to provide.

The step budget (`conversation.goal-steps`) is 10, so a chain of that length fits.

## What to take from it

*Re-planning is right; re-deciding is not.* The re-plan exists so the command goes through
the checks again. It was also re-making choices that had already been made and shown to
somebody — which is not verification, it is a second opinion nobody asked for.

*A guard that silently declines to act is only half-built.* `expect` correctly refused a
command that no longer matched. What was missing was any way for the operator to learn that,
and the difference between "refused" and "did nothing" is invisible from a card.

## Verified by

`ConversationServiceTest` — `aProposalCarriesTheValuesItWasPlannedWith`,
`aProposalCarriesTheActionItWasPlannedAs`, `aProposalWithNoValuesCarriesNoneRatherThanNull`,
`whatThePlanRanOnIsKeptWithTheTurn`, `theActionThePlanSettledOnIsKeptWithTheTurn`,
`aProposalCanBeTurnedDown`, `aDeclinedProposalStopsBeingOffered`,
`somebodyElsesProposalCannotBeTurnedDownEither`.

`ConsoleHistory.test.tsx` — "can turn a step down as well as approve it", and "approves by
turn id, never by sending the command back".
