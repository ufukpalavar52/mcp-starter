# 21 — One card for a whole plan

Approving every action separately was costing two decisions where there was one.
"Write this script to /tmp and run it" meant two cards, two model calls and two waits —
and the person read the same thing twice to answer the same question twice.

The change itself is small. What is worth recording is that **the batching was never what
broke.** Three separate faults turned up while testing it, in three different services,
and every one of them was the same stale assumption: that a job runs one action.

## Where the line is

A command can only be approved if it can be shown.

| Plan | One card | Why |
|---|---|---|
| "Write this and run it" | yes | Both commands resolve from the one sentence |
| "Find the Yigits and delete them" | **no** | The delete has no command at planning time — the id comes from the search's answer |

Batching the second would mean approving something nobody has seen, which is the one
thing the approval path exists to prevent. So: **no action waiting on an earlier answer,
or no batch.** The distinction already existed in the code; nothing new had to be invented
to draw it.

## The guard got stricter, not looser

`_matches` compared the plan against the one approved command. It compares multisets now,
and demands equality:

| | |
|---|---|
| A third command appears after a re-plan | refused |
| One of them changed | refused |
| One of them went missing | refused |
| The same command twice, approved once | refused |

Containment would wave the first through. A *set* comparison would wave the last through —
collapsing a duplicate lets a plan run something twice on the strength of having been shown
once. **A wider approval has to be a narrower check, not a looser one.**

## The three that assumed one action per job

None of these was visible until a job actually carried two. Each produced a different
symptom and none of the symptoms pointed at the cause.

**The output never reached the screen.** `findByRef` returned `runs.getFirst()`, under a
comment reading *"the first is the one the caller named"* — true for as long as a job had
one. The console showed the write, which prints nothing, while the output sat unread behind
it. A run that had succeeded looked like a run that had printed nothing.

**The poll stopped on it.** `cat > file` settles in a moment; the command that runs the file
is still going. The card read the first action's status, declared the job finished and
stopped asking. The output arrived seconds later to a screen that had stopped looking —
which is why waiting did not help, and why this read as "it just doesn't work".

**The goal loop ran once per action rather than once per job.** This was the bad one. The
same goal was evaluated twice, and the second answer did not have to agree with the first:

```
Goal 47 is met after 1 step(s): the script has been written and executed
Goal 47 continues: run the Python script ...
Goal 47 continues: The goal has been met: ...
```

The first was right. The second proposed running the script it had just run. The third
turned the model's own *"the goal has been met"* into a request, which the planner
faithfully resolved to `echo 'Script has already been written and executed successfully.'`
and put up for approval.

**Asking a model the same question twice earns the right to two different answers.** The
fix is not a better prompt; it is asking once. Only the action that finishes last advances
the goal.

## Two more from the same root

**A step's account of itself held one command.** Told only "the file was written", the model
reasonably concluded the file still needed running — and asked to do again what the same
job had already done.

**A goal's own values did not reach its later steps.** The path in "write this to
/tmp/fib.py and run it" is given once, and the write prints nothing, so the run step had no
answer to recover it from and was refused for an input that had been supplied. They sit
*under* whatever the loop read out of a result, never over it: for a goal working through
several records, that ordering is the only thing telling one record from the next. The rule
it must not break is older and still stands — an unattended step may not route a sentence
for values, because a model asked to find one in "Processing the first user found with
first_name 'Yigit'" produced an id nobody had mentioned and sent a DELETE to approval
against it.

## What this cost, and what it is worth

Four rounds of "I tried it, it didn't work", each reporting a true observation that pointed
somewhere other than the cause: *no output* was the run lookup, *still no output* was the
poll, *it asked again* was the loop, *it asked to echo something* was the loop a third time.

The lesson is not about approval. It is that **a change to how many of something there can
be is never local.** The batching was ten lines of decision. Everything downstream that had
written `getFirst()` — a repository lookup, a poll, a listener, a description handed to a
model — had encoded "one" without saying so, and each did something plausible and wrong
rather than failing.

Worth asking of the next such change: what else counts these?

## Verified by

Unit tests at each layer — the multiset comparison in mcp-server, the batch gate and the
once-per-job rule in the gateway, the card and the poll in the panel — and four rounds
against the running stack, since none of the three faults was reachable from the source
alone.

| | |
|---|---|
| One card | two commands, one approval |
| The job | both actions under one reference, both succeeded |
| Output | both blocks, the second carrying the answer |
| Approvals after | none |
| "Find and delete" | still one step at a time, as it must be |
