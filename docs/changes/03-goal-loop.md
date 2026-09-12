# 03 — The goal loop

## The problem

One prompt could only ever become one action. "List the fees, then total them" is
one goal and two queries; the router picks one tool, that tool's action writes one
statement, and a guardrail refuses two statements in one — so a goal had nowhere
to become two.

## How it works

`GoalLoop` is driven by results arriving, not by waiting for them. A step cannot
be decided until the one before it has answered, and a prompt that blocked for
that would hold an HTTP request open for as long as the database takes.

```
run finishes ──▶ RunResultListener ──▶ GoalLoop.advance
                                          │
                                          │  goalOf(runRef): the goal and its steps
                                          │  nextStep(...):  one more request, in words
                                          ▼
                                  the ordinary prompt path
```

What comes back from the step planner is a **sentence**, not a plan. It goes back
through routing, planning and the guardrails exactly as a typed question does, so
the loop adds a decision and no new way to reach a database.

Every reason to stop is checked in code rather than asked of a model: the step
budget, a step that failed, work that was not a read. A loop that asks whether to
continue can be told yes forever.

The loop runs as the person whose goal it is — their identity, not the process's.
It is their conversation, the step is planned against their permissions, and an
audit trail saying "system" for work somebody asked for would name the wrong
actor.

## Then SSH was let in

Shell goals need this more than query goals do: "install apache and start it" is
two commands and the obvious way to write it is a chain, which the guardrails
refuse.

The two kinds are not the same proposition, so they are not treated the same:

| | Queries | Shell commands |
|---|---|---|
| Steps run | automatically | only after a person approves |
| Rules given to the step planner | read-only, name only these tables | may change the machine, one command's worth per step |
| What a step summary carries | row count, columns, first rows | what the command printed |

A shell step is **always** held for approval, whatever the action's own setting
says — the loop chose the command, nobody typed it, and the machine it lands on is
real.

## Two bugs found while proving it

**Compound step sentences.** The step planner wrote "finish the installation and
then start the service". Re-planned, that produced the install — which had already
run. The rules now forbid "and then" and forbid restating work already done.

**The plan could change under the approval.** Planning is not deterministic, so a
step approved as `systemctl start httpd` could be re-planned into something else
on its way to running. See [06-approval.md](06-approval.md).

## What a step has to carry with it

The loop passes one thing between steps — a sentence — and that turned out to be too little
twice over. The record to act on is not in it, and neither is the operation: "processing the
second user found" names a row and no verb. Both are now carried explicitly, and the several
places they were being lost are in [15](15-carrying-a-value.md).

## Verified live

```
"sunucuya apache kur ve calistir"
  turn 118  →  sudo dnf install -y httpd      ran, exit 0
  turn 119  →  sudo systemctl start httpd     AWAITING APPROVAL, nothing ran
  after approving                             ran, exit 0
  systemctl is-active httpd                   → active
```

## Verified by

`ConversationServiceTest` — `goalOf` walking the chain, a proposal being
approvable only by its owner, an already-run step not being approvable twice.

`test_planner.py` — the shell rules are not the query rules, a shell step is asked
for in words, a step may not be two things joined by "and then", and a `db` goal
still gets the read-only rules.
