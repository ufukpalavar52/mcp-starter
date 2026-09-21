# 25 — Nobody was listening

A console request sat on "waiting for the result" for eight minutes. The run was `running`,
had no targets, and the job was on `mcp.actions` with **zero consumers**.

Every one of the six services reported itself as running. `docker compose ps` showed the
broken one as up and the healthy ones as ordinary. Finding it took reading container logs.

## What had happened

On 19 September a machine restart brought five containers up inside four hundred
milliseconds of each other. `mcp-action` started a hundred and fifty milliseconds after
`mcp-config` — far too early to be answered — and fell back to its local defaults: broker
`127.0.0.1:5672`, which inside a container is the container, and no cipher at all.

The compose file declares `depends_on: mcp-config: condition: service_healthy`. That orders
a `compose up` and nothing else: **when Docker restarts containers by restart policy it
ignores `depends_on` entirely.** A dependency that only holds on the happy path is not a
dependency; it is a comment.

It then retried the broker a hundred and thirty-two times over thirty-seven hours and never
once asked whether configuration might be available by now — which it was, seconds later.

## Retrying one half of a start up forever and the other half never

That asymmetry is the whole defect, and it is worth stating on its own because it is easy to
build again. A supervisor was written for the broker, carefully, with backoff and jitter and
a rule about which failures are permanent. Configuration got one attempt at process start.

So the service could recover from every outage except the one it actually had.

A dial that follows a fallback now re-reads configuration first. Only after a fallback: a
service that got its settings has no reason to keep asking, and re-reading on every
reconnect would let a central edit move a running executor to a different broker with
nothing said about it.

The cipher is rebuilt with it, because both come from that same failed read. Recovering the
broker alone would have been the worse half of a fix — the executor would start taking jobs
it cannot open credentials for, turning silence into a run of clear failures.

## A screen that was telling the truth

"Waiting for the result" was correct for thirty-seven hours. Nothing had failed. No error
existed to display, no status was wrong, and every retry was working exactly as designed.

This is the fourth time in this project that the fault was not broken behaviour but a
system saying the wrong thing about itself — see [24](24-ways-in.md). The pattern is now
familiar enough to name: **a correct statement that leaves the reader with no next step is
a defect in the same way a wrong one is.**

The gateway now asks the broker something it has always been able to answer: how many
consumers are on the job queue. A run that is unfinished, dispatched more than twenty
seconds ago, and waiting on an empty queue is reported as `stalled`.

Three decisions inside that:

**It is not folded into `status`.** The run really is running as far as the gateway is
concerned. Rewriting the status would be this service inventing an outcome nobody observed,
which is the same class of lie in the other direction.

**The count is asked, not inferred from silence.** A command can print nothing for ten
minutes and be perfectly healthy; `tail -f` prints nothing until something happens. Time
alone cannot tell a quiet command from an empty queue, and a warning that fires on both
would be ignored within a week.

**Uncertainty answers "fine".** A broker that cannot be asked returns `stalled: false`.
Telling somebody their run will never finish, wrongly, sends them hunting a fault that is
not there — which is precisely the cost this field exists to remove.

The card drops the spinner when it fires. A spinner is a claim that something is happening.

## And the same day, the log said nothing at all

A prompt came back to the screen as:

> Could not route the prompt: I/O error on POST request for
> "http://mcp-server:8000/api/v1/prompts": Request cancelled

The gateway's log held **nothing for that minute**. Not the error, not the request, not a
line. Meanwhile the MCP server's log showed two model calls answering `200 OK` seconds
apart and then stopping mid-handler — so the process that knew why the call was abandoned
was the one that said nothing about it, and the process that was working was the only one
that left evidence.

The cause was one missing line. `GlobalExceptionHandler` logged Redis outages at error and
data access failures at error, and handled every `ApiException` — including the 503 that
this was — silently. A deliberate status is not the same as an uninteresting one.

It now logs `ApiException` when the status is 5xx, with the cause attached, and stays quiet
for 4xx. Both halves matter: a tool that was not found and a password that was wrong are
ordinary traffic, and logging those would bury the entries that matter among the ones that
do not.

**An error somebody can read on a screen and not find in a log cannot be diagnosed twice.**

What actually cancelled that request is still unestablished — a first model call slow
enough to exhaust the two-minute budget, or the caller going away. Nothing was dispatched
and no run was created, so nothing ran. The next occurrence will say which, which is the
whole point of the change.

## What stayed out

**Marking stalled runs failed.** Tempting, and wrong: the job is still on the queue and an
executor coming back will run it. A run marked failed that then executes is worse than one
that honestly says it is waiting.

**An acceptance message from the executor.** It would separate "nobody took it" from "taken
and quiet", which the consumer count does not. It needs a protocol change and a column, and
the consumer count answers the question that actually came up.

## Verified by

| | |
|---|---|
| running, nobody on the queue, settled | stalled |
| running, an executor listening | not stalled |
| dispatched two seconds ago | not stalled |
| finished | never stalled |
| broker unreachable | not stalled, at any age |
| fell back, config server returns | adopted on the next dial |
| read from mcp-config | never re-read |
| fell back, config server still down | fallback kept, dial unchanged |
| a 5xx ApiException | logged at error, with its cause |
| a 4xx ApiException | not logged |

## The operational note

`depends_on` does not survive a daemon restart. Any service in this stack that reads its
configuration once at start up has the same latent fault; `mcp-action` is the one that hit
it. The general fix is the one applied here — re-read after a fallback — rather than trying
to make container ordering reliable, which it is not.
