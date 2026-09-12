# 18 — Where the logs go

Six services, six terminals, and nothing that could answer "what happened at 11:04?" across
more than one of them — or "what did this person do?" across any of them. This is a log
store, a way to read it, the work of getting each service to write something a shipper can
find, and putting the acting user on every line.

## The stack

| Part | Image | Job |
|---|---|---|
| Loki | `grafana/loki:3.7.2` | Stores the lines, indexed by label |
| Grafana | `grafana/grafana:13.2.1` | Reads them |
| Alloy | `grafana/alloy:v1.19.2` | Tails the files and ships them |

It lives in `mcp-starter/observability`. Every port is bound to `127.0.0.1`: Loki has no
authentication in front of it, so on a shared network this is production output available to
anyone who asks.

**Alloy rather than Promtail.** Promtail reached end of life in early 2026 and takes no
further fixes. The file tailing is the same job.

## Each service writes its own file

The services are local processes, not containers, and none of them wrote a file: Spring
Boot, uvicorn, the Go binaries and `next dev` all write to stdout. Files existed only where
a shell redirect put them — which meant the whole arrangement worked until somebody started
a service from their IDE, and then quietly stopped.

| Service | How |
|---|---|
| `mcp-server` | `RotatingFileHandler`, 10 MB × 5 |
| `mcp-gateway`, `mcp-config` | `logging.file.name`, logback's rolling policy, 10 MB × 5 |
| `mcp-action`, `mcp-cipher` | `io.MultiWriter(os.Stdout, file)` |
| `mcp-panel` | `npm run dev:logged`, through `tee` |

All six read `MCP_LOG_DIR`, defaulting to `~/mcp-logs`.

**The console is kept in every case.** Both, not either: the console is what an IDE shows
and what somebody watching a terminal reads; the file is what a shipper can tail after they
have gone home. Choosing between them loses one of those.

**No rotation on the Go side.** It would mean a dependency, and those two write far less
than the Java services — but a process left running for weeks will grow a large file.

## Labels, and what does not become one

`service_name`, `level` and `source`. Nothing else.

Every distinct combination of labels is a separate stream in Loki, so a label that varies
per line — a request id, a run ref, a user — multiplies the streams until queries crawl.
Those belong **in** the line, where `|=` and `| json` still find them.

`service_name` comes from the file name; `level` is parsed out of the line.

## Who asked, on every line

A log that says what happened and not who asked for it answers half the question. The
identity lived in the gateway's database, on the run row, so "show me everything this
person did" had no answer that did not involve SQL — and none at all that crossed more
than one service.

It rides along now, through all three services a request passes through:

| Service | How |
|---|---|
| `mcp-gateway` | A filter puts the id in MDC; `logging.pattern.level` puts MDC on the line |
| `mcp-server` | A `ContextVar` set at the top of the endpoint, read by a logging filter |
| `mcp-action` | `actorId` on the job; the worker's logger carries it with `With` |

```logql
{service_name=~"mcp-.+"} |= "actor=3"
```

Three services, one query.

### The id, not the address

The same question, answered the same way — and the name is one lookup away in `users`.

What it avoids is the point. An email in the logs is personal data in six files and a store
with no encryption and thirty days of retention. This stack seals query output for exactly
that reason: the rows a query returned are sealed through mcp-cipher because a control plane
has no business keeping them in the clear. Writing addresses into the logs beside them would
undo that arrangement one line at a time.

The actor is a value on the line rather than a label, for the reason above: a label per
user is a stream per user.

### Where MDC bites

`MDC` is thread-local and a servlet container hands the same thread to the next request.
Left behind, one person's id labels another person's work. It is removed in a `finally`,
and that is not a detail: **a log that is wrong about who did something is worse than one
that does not say.**

The Python side has the matching hazard with a different shape. A `ContextVar` rather than a
thread local, because the server is async: one thread serves many requests, interleaved, and
a thread local would hand whichever of them spoke last to whichever is logging now.

The logging filter is attached to the handlers, not the root logger. A filter on a logger
runs only for records made through that logger; a line from a library's own logger would
reach the handler with no `actor` attribute at all, which the format string turns into an
exception, swallowed, and the line is lost.

### Nobody is a value too

A step the goal loop wrote has no person behind it. Those log `actor=-` rather than an empty
field: an empty value reads as a missing one, and `-` says there was nobody to name.

## What was wrong on the way

### A healthcheck that could never pass

Loki was marked unhealthy on the first `up`, and the two services waiting on it never
started. The healthcheck was `wget -q -O- .../ready` — and the Loki image is distroless. No
`wget`, no `curl`, no `/bin/sh`. There is nothing inside that container to run a check with.

Loki itself had been working the whole time.

The check is gone and the dependencies are start-order only; readiness is asked from
outside, with `curl -s localhost:3100/ready`. **A container with no shell cannot run a
shell-based healthcheck, and one that always fails is worse than none** — it holds back
everything that waits on it.

### A filter that quietly answered with a third of the matches

`level` was parsed case-insensitively and kept whatever case the line used, so six services
produced `ERROR`, `Error` and `error` as three separate labels. `level="ERROR"` returned the
errors from two services and said nothing about the other four.

It is upper-cased now, and `WARNING` folded into `WARN`. **A filter that silently returns
some of the matches is worse than one that returns none.**

### A template that failed and said so to nobody

The first fix for that was one pipeline: `{{ .level | ToUpper | Replace "WARNING" "WARN" }}`.
It changed nothing, and Alloy logged no error — a template stage that fails leaves the value
untouched. `Replace`'s signature did not match, so the whole expression was abandoned,
`ToUpper` included, and the fix looked applied.

Two stages now, so one failing call cannot undo the other.

### Test runs that wrote into the home directory

`mcp-server`'s suite left 63 KB in `~/mcp-logs` on every run. File logging is on by default,
which is what makes it work for somebody who configured nothing; under test it made the
suite leave something behind on the machine it ran on.

A fixture did not fix it. `app/main.py` ends with `app = create_app()` — which is what lets
uvicorn say `app.main:app`, and it runs on **import**, during collection, long before any
fixture. The file was already open. It is now set at the top of `conftest.py`, before
anything imports the application.

The Spring suites had the same problem and a different shape to it — see below.

### A test fixture that shadowed the configuration it needed

`mcp-config`'s suite was already failing — nine errors, `CONFIG_PASSWORD is not set` —
before any of this. The fix looked obvious: add `src/test/resources/application.yaml` with a
synthetic password.

It made things worse. A file of that name **shadows the main one entirely**, and the main
one is where this server is told to read plain files instead of cloning a git repository.
Shadowed, it went looking for a git URI it has never had.

Removing the file did not help either, because Maven **copies** test resources into
`target/test-classes` and deleting the source does not delete the copy. Two runs were spent
on a file that was no longer there.

The properties belong on the test classes, where `ServedConfigurationTest` had been putting
them all along:

```java
@SpringBootTest(properties = {
        "spring.security.user.name=test",
        "spring.security.user.password=test",
        "logging.file.name=",
})
```

Why not the resources directory is now written at the top of the class, so the next person
does not try what I tried.

### An hour spent on three consumers

The `actor` field was correct in the source, and missing from the executor's live output.
What followed: reading the code, rebuilding with `-a` to bypass the build cache, proving
`slog.With` in a scratch test, inspecting the symbol table. All of it confirmed the change
was right, which it was.

Three processes were consuming `mcp.actions` — two left from earlier in the session, both on
old code — and the broker was handing most jobs to them. `ps` with a pattern had missed them
because their paths varied between builds.

The trap was already written down, in [10](10-traps.md), with the command that would have
answered it in ten seconds. What that file now also says is the faster route, which only
exists because of this work: `lsof ~/mcp-logs/mcp-action.log` names every process holding
that service's log open — by what it is doing rather than by a path.

### A week-old process holding the port

`mcp-cipher`'s new code never took over: port 9090 was held by a process started **seven
days earlier**, and the pattern used to kill it did not match its path. The new one logged
`address already in use` and exited.

Only noticeable because its lines in Loki stopped being fresh. Find these by port, never by
pattern — which is [already written down](10-traps.md), and was read too late.

## Silence is not a break

The first question asked of the finished thing was "are logs reaching Loki?", and the
ten-minute window was empty for all six services. That reads as a broken pipeline. It was
not: the newest line in Loki was 212 minutes old, which was exactly the mtime of every log
file. The services had nothing to say — nobody was using them.

The pipeline was proved by writing a line and watching it arrive, six seconds later. Then by
making a real request and watching the gateway's file grow.

**An empty window means one of two things, and they are not the same.** Asking Loki proves
nothing about the source; the only way to tell them apart is to make something happen.

## The first thing it caught

`mcp-action` was down. It had died some time after 11:49 and nothing said so — it is a queue
worker with no port to fail a health check on, so a command sent from the console would have
sat in the queue looking submitted.

What gave it away was its lines in Loki not being fresh while the others moved. That is the
whole point of collecting six services into one place, and it happened on the first day.

## Verified by

Against the running stack, because none of this is provable from the source.

A line written into a file appeared in Loki within seconds, labelled `service_name` and
`level` from its name and its text. All six services were restarted onto the new code and
all six appeared. `mcp-*.log` collected the stack's files and left twelve unrelated `.log`
files in the same directory alone. `curl` through Grafana's datasource proxy returned the
label set, so the reading side is connected too.

The level normalisation was checked on fresh lines after the fix, not on the ones already
stored: `error` arrived as `ERROR`, `WARNING` as `WARN`.

For the actor: a real request through the panel's own path, then
`{service_name=~"mcp-.+"} |= "actor=3"` in Loki, which returned a line from each of the
three services. The executor's half has tests of its own —
`TestAJobsLogLinesNameTheActingUser` and `TestAJobWithNoActorSaysSo`, written against the
handler's real output, because what matters is that the field reaches the line and only the
logger can say so.
