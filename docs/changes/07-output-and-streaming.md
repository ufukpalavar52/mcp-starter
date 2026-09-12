# 07 — Output, and following a log

## "The commands run but I see no output"

Everything worked — the command ran, the output came back, was sealed, opened and
served — and the console drew nothing. One line:

```tsx
{target.rows ? <ResultTable rows={target.rows} /> : stdoutExcerpt}
```

An empty array is truthy. Every SSH command came back with `rows: []`, took the
table branch, and had "matched no rows" drawn over the top of the output it had
actually produced.

`rows: []` came from two places:

- **`RunOutputCipher.seal`** built the envelope with `Map.of`, which refuses null,
  so a null rows list became `List.of()`. That erased the only distinction the
  field carries: no rows **at all**, which is what a command has, against no rows
  **matched**, which is a query's answer.
- **`RunResultRecorder.rowsOf`** decided by whether anything had been printed
  rather than by the kind of action. `ls` in an empty directory prints nothing and
  still has no rows.

Both fixed, and the render now checks length rather than truthiness — a table with
nothing in it is a query's answer and never a command's.

## "(no rows)" for a command

Related, and the reason a working `ls` looked broken: a command that printed
nothing was reported with a phrase about queries, which reads as the tool having
failed to fetch something.

| Case | Was | Is |
|---|---|---|
| Query matched nothing | `(no rows)` | `(no rows)` |
| Command printed nothing, exit 0 | `(no rows)` | `(no output)` |
| Command failed, nothing on stdout | `(no rows)` | nothing — the reason is in stderr |

The last one is its own fix: claiming "returned no output" on a non-zero exit is a
success claim that contradicts the stderr beside it.

## Following a log

`tail -f` was not merely unsupported — it wedged the stack. The executor waited
for the command to finish, so a command that never finishes held the single worker
for the full ten-minute job timeout and returned its buffer as `cancelled`.

The design chosen was chunks over the queue, read by the polling the panel already
does. No new transport, no connection lifecycle, no SSE.

```
session.Stdout ─▶ tap ─┬─▶ the buffer the final result is built from
                       └─▶ pending, flushed once a second
                                  │
                          mcp.progress (not durable, capped, 60s TTL)
                                  │
                          gateway: RunProgress, in memory
                                  │
                          GET /api/v1/runs/{ref} while unfinished
```

Held in memory on purpose. The output is stored once, sealed, when the result
arrives; persisting the same bytes again would mean production data in two places,
one of them re-sealed thirty times a minute for a screen nobody may still be
watching.

Following is **opt-in**. With the box unticked the session writes straight into the
buffers, exactly as before.

### The window is idle, not fixed

First built as a fixed window, which was wrong in both directions: it cuts a busy
log off mid-sentence and spends its whole length on a silent one. It is now a
watchdog — every line printed starts the window again — with a hard ceiling of 600
seconds, because an idle window is no bound at all on a log with a line every
second.

A follow that ends by its own window reports **`succeeded`**. `tail -f` never stops
on its own; being stopped is how "watch until it goes quiet" finishes, and filing
that as `cancelled` would put a successful watch alongside the runs somebody
interrupted. Which end it was is told by **which context closed**, not by elapsed
time: the follow window is nested inside the one the job and the operator's cancel
act on.

## Workers, and a setting that did nothing

Raised to 5 in `config-repo/mcp-action.yml` so a follow does not block everything
behind it. On its own that changed nothing: prefetch was fixed at 1, so the broker
held every other message back and five workers took turns on one job.

Prefetch is now the worker count — enough for every worker to have something, and
not one more, because a buffered job is a job another executor could have run.

Proven by a test that fails against the old behaviour:
`only 1 of 3 jobs were running at once`.

## Verified live

```
df -h                  → rows: None, stdout: Filesystem  Size  Used Avail…
ls (empty directory)   → rows: None, stdout: (no output)
tail -f, quiet log     → data at t+2s, still open at t+113s, ended t+123s
follow + uptime        → uptime finished while the follow was still running
```

## Verified by

`RunResultRecorderTest` — a command that printed nothing says so in its own words,
a failed silent command stores nothing, and a command's output travels with no rows
beside it.

`RunProgressTest` — chunks accumulate in order, each host is its own log, the end
is marked, the newest lines are the ones kept, and a finished run still shows its
last lines for a while.

`follow_test.go` — output is kept as well as forwarded, taking twice returns only
what is new, the last chunk is sent when the command ends, output postpones the
end, silence ends the watch, and cancelling the job ends it too.

`worker_test.go` — workers run jobs at the same time.

`RunOutcome.test.tsx` — a command's output shows even when the rows field came back
empty, and a running command's output is shown before it finishes.
