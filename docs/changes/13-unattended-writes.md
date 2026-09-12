# 13 — A delete that nobody approved

> A record was deleted during testing. What follows is why, and what stops it now.

## What happened

Proving the goal loop end to end, "find the user called Mehmet Bulut and delete them" ran:

```
turn 212  GET    ?first_name=Mehmet&last_name=Bulut   → id 90
turn 213  DELETE /api/users/90                        → 200, deleted
```

The second step was never shown to anybody. The record was re-created afterwards from the
first step's output, which is the only reason the data still exists — with a new id, because
the API assigns them.

## Why the gate did not hold

Approval was decided in the loop, from the run that had just **finished**:

```java
runsUnattended(finished)   // finished = the GET, a read → no approval needed
```

But the step about to run was the DELETE. And which action a step lands on **is not known
there**: the loop writes a sentence, and what that sentence resolves to is decided later, by
routing and the planner.

So a read was taken as licence for whatever came next.

## Where the decision belongs

Where the plan is known. The loop no longer decides; it sends the step marked as written by
nobody, and the MCP server holds anything unattended that changes something:

```
loop → prompt(unattended: true) → plan → does anything here write?
                                          ├─ yes → awaiting_approval
                                          └─ no  → dispatch
```

"Writes" is read off each action's own settings rather than guessed from its kind:

| | Writes |
|---|---|
| REST | by method — GET, HEAD, OPTIONS read; everything else writes |
| DB | unless the action was declared read only |
| SSH | always — what it does is written at run time |

A read still runs on its own, which is what makes a goal of queries worth looping at all.
And a write somebody **typed** is not held by this rule: they asked for it, and the action's
own approval setting is still there for those.

## Then approval refused everything

With the gate working, approving the held DELETE came back as *"the plan changed since it
was approved"* — against a plan that had not changed at all.

`_matches` compared **every** action in the plan with the approved command, including the
ones set aside. Those resolve to nothing — there is no point resolving what will not run —
so no approval of a multi-action definition could ever match. `skipped` was added later and
this comparison was not revisited.

## The whole chain, working

```
"ismi Mehmet soyadı Bulut olan kullanıcıyı bul ve sil"
  ├─ selection: GET and DELETE chosen
  ├─ deferral:  DELETE set aside, waiting on id
  ├─ GET runs → id 102
  ├─ loop reads the recorded deferral, writes the delete step with the id
  ├─ DELETE planned → it writes → AWAITING APPROVAL
  └─ approved → runs
```

## What to take from it

Two of these were the same mistake in different clothes: **a decision made where the
information is not**. The loop judged approval without knowing the action; `_matches`
compared actions it had no reason to compare. Both looked reasonable in the diff.

The third is smaller and worth saying anyway: a near-miss earlier in the same work
(`DELETE /api/users/0`) was stopped only because an unrelated POST failed first. Being
saved by somebody else's validation is not being safe.

## Verified by

`test_api.py` — a write nobody typed is held, a read nobody typed still runs, a write
somebody typed is not held by this rule, the actions set aside are not part of the approval
comparison, and a plan where everything was set aside matches nothing.
