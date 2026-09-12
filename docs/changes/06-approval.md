# 06 — Approval

## Two dead flags

The SSH action had `requireApproval` and `dryRun`. Both were stored in the panel,
carried through the gateway, reported on the plan — and read by nothing. A prompt
with "execute" ticked dispatched the command regardless, which is the one thing
the approval box exists to prevent. `dryRun` defaulted to **on** and promised
"report what it would do".

They were merged into one mechanism: `requireApproval` became real, `dryRun` was
removed. Two settings promising the same thing, neither of them working, is worse
than one working setting.

> Superseded in one respect: a step the goal loop wrote is now held whenever it changes
> something, whatever the action's own setting says. See
> [13-unattended-writes.md](13-unattended-writes.md) — that rule was added after a delete
> ran unapproved.

## Two gates, two different questions

```
plan produced
     │
     ├─ is the plan even valid? ──── no ──▶ refused (nothing to approve)
     │
     ├─ has anybody agreed? ───────── no ──▶ awaiting_approval
     │
     ├─ is this what they agreed to? ─ no ──▶ refused, re-approve as it now reads
     │
     └─ dispatch
```

The second gate exists because **planning is not deterministic**. A goal-loop step
proposed as `systemctl start httpd` was approved on the strength of that command,
re-planned on its way to running, and came back as the install instead. It ran.
Nobody had agreed to it — they had agreed to the other one.

So an approval carries `expect`: the command that was on screen. It is not a way
to supply a command — what runs is still what the planner writes and the
guardrails pass — it only refuses to run anything else.

The first gate was a bug found while testing the others: a rejected plan was being
offered for approval, putting a button under a refusal and asking somebody to
decide about a command that is not there.

## Approving fills the turn in, rather than answering beside it

The first version recorded the approval as a **new** turn. The proposal stayed
exactly as it was — still planned, still with no run behind it — so it went on
offering to be approved, and every press ran the command again. In the database:

```
151 | ls -lah /etc | executed=t | ran=f   ← the proposal
152 | ls -lah /etc | executed=t | ran=t   ← approving it
153 | ls -lah /etc | executed=t | ran=t   ← pressing again
```

`complete(turnId, result, failure)` now updates the same row. The sentence and the
goal it belongs to are the proposal's own and do not change; everything else is
the outcome, which the proposal did not have until then. Pressing again returns
404.

## What counts as awaiting approval

Derived by the gateway rather than assembled in the browser — a copy of the rule
in the client is the one that drifts:

```java
runRef == null && "planned".equals(status) && (goalTurn != null || executed)
```

Two turns match. A step the loop wrote, which nobody typed. And a question
somebody typed with the box ticked against an action that asks for approval — they
asked for it to run, and the action says a person sees the command first.

A plan-only turn is not one of them: nobody asked for it to run, so there is
nothing to say yes to, and a button on every one of those would be noise.

## A null turn id, found on the way

Approving needs a turn id, and the prompt response was returning `null` for every
turn but the first in a session. A conversation loaded from the repository is
already managed, so saving it **merges** rather than persists: the cascade writes a
copy of the turn and the instance in hand never receives an id. It is now read back
off the saved conversation.

## What came after

Two halves of this were still missing and are covered in
[16](16-approving-a-command.md): there was no way to say *no*, and approving re-planned
from the turn's sentence alone — so the command that ran was not always the command that
had been shown.

## Verified by

`ConversationServiceTest` — approving fills in the proposal rather than appending
beside it, an approved proposal stops offering to run, a step of somebody else's
goal is not approvable, a rejected plan is not a proposal, and a failure is kept on
the turn it belongs to.

`test_api.py` — nothing is dispatched until somebody approves, approving the
command in front of you dispatches it, approving a **different** command does not,
and an action without the box runs as before.

`ConsoleHistory.test.tsx` — the console offers a proposed step without running it,
and approves by turn id rather than by sending the command back.
