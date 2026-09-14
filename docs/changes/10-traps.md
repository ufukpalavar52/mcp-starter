# 10 — Traps

Things that cost real time, usually more than once. Each looked like a bug in the
code being written and was not.

## `go run` leaves a child behind

`go run ./cmd` makes two processes: `go run` itself and the binary it compiled at
`…/go-build*/b001/exe/cmd`. The **child** is what holds the queue consumer, the
port, and the job. Killing the parent leaves it running, so starting a fresh copy
gives two consumers on `mcp.actions` — and the job goes to whichever the broker
picks, usually the old one.

This bit four times. Every time it looked like "my change did nothing"; every time
the process taking the work was the previous build. The diagnosis is expensive
because the logs stay quiet: the new process sits idle and the old one runs
normally.

The fourth time cost an hour, and this section was already written. An added field
was missing from the executor's log lines, so the code was read, the binary
rebuilt with `-a` to bypass the build cache, `slog.With` proved in a scratch test,
and the symbol table inspected — all of it confirming the change was correct,
which it was. Three consumers were on the queue: two from earlier in the session,
both on old code, and the broker was handing most jobs to them.

**When a change appears to do nothing, count the consumers before reading the
code.** It takes ten seconds and it is the likeliest answer.

The pattern alone is not enough to tell them apart, either — the child's path is
sometimes `…/T/go-build*/b001/exe/cmd` and sometimes
`~/Library/Caches/go-build/*/…-d/cmd`, and the second shape is what mcp-cipher
looks like too. The reliable test is the connections:

```
lsof -nP -p <pid> | grep -E '9090|5672'
```

mcp-cipher **listens** on 9090; mcp-action **connects** to 9090 and 5672.

Then confirm:

```
docker exec rabbitmq rabbitmqctl list_queues name messages consumers
docker exec rabbitmq rabbitmqctl list_consumers
```

`mcp.actions` should show **one** consumer. Two means the old process is still up.

Now that every service writes a log file, there is a faster way to the same answer:

```
lsof ~/mcp-logs/mcp-action.log
```

Every process with the file open for writing is a live copy of that service. This
is better than `ps` with a pattern, which is what missed them: it names the
processes by what they are *doing* rather than by a path that varies between
builds. It works for the Java and Python services too.

## `@Transactional` on the wrong method

Adding `approve()` above `prompt()` in `ToolExecutionServiceImpl` left the
`@Transactional` annotation attached to the new method, and `/api/v1/tools/prompt`
started returning 500 with `LazyInitializationException`. Annotations belong to
what follows them; inserting a method between an annotation and its method moves
it.

Related, and worth remembering separately: a `default` method on the service
interface calling another method of the same interface is **self-invocation**. It
bypasses the Spring proxy, so `@Transactional` does not apply. A convenience
overload written that way produced the same exception.

## Go's `omitempty` and Jackson records

Go leaves out a field that is zero or false. Jackson gives a record's missing
component `null`, and a primitive cannot take null.

Every ordinary progress chunk has `done` false, so every ordinary chunk was
refused. The live view stayed empty and the only sign was a stack trace per second
in a log nobody was tailing. Box the optional fields — `Integer`, `Boolean` — on
anything a Go service publishes.

## `./mvnw` flags

Never `-o`. The repository is an internal artifactory and an offline build fails on
artifacts that were never cached.

Never `-q`. A slow artifactory fetch then looks exactly like a hang, with an empty
log for minutes.

## Slow tests are not local

New follow tests waited on real time — about six seconds in the executor package.
`go test ./...` runs packages in parallel, and that was enough to make a
pre-existing timing sensitivity in the reconnect test fail. It passed alone and
with `-p 1`.

The fix was in the code rather than the test: the watchdog now ticks at
`min(1s, idle/4)` instead of a fixed second, which is also better behaviour — a
five second window noticed a second late is a fifth of it, and a window shorter
than the tick would never be noticed at all.

## A field added later, a comparison not revisited

`skipped` was added to a planned action, and `_matches` — which compares the approved
command with the re-planned one — went on comparing every action including the ones set
aside. Those resolve to nothing, so no approval of a multi-action definition could match,
and it presented as "the plan changed since it was approved" against a plan that had not.

Adding a field to a shape means finding everything that iterates it. `grep` for the type,
not for the field.

## Deriving from what was already thrown away

Reading rows out of a REST answer was written to happen when somebody asks, so that what is
stored stays exactly what the endpoint said. It returned nothing, every time.

The full body is never stored — the recorder trims it to four thousand characters before
sealing — so there was nothing to read. The reasoning was right and the data it needed was
not there.

Before choosing *when* to derive something, check what survives to that moment.

## Server data has no client ids

The editor keys header rows by `id`, and `createAction` gives new ones an id. Headers loaded
from the gateway are `{key, value}` — spreading the stored config over a blank action
replaced the ids with nothing, and every row rendered with an undefined key.

The same shape appears wherever a client-side list identity meets a server-side document.
Give them ids when mapping in, not when rendering.

## Two settings promising the same thing

`dryRun` and `requireApproval` both existed, both were stored and carried through
three services, and neither did anything. A setting that does nothing is worse than
a missing one: somebody ticks it and believes they are protected.

Before adding a flag, follow it to the place that reads it. Both of these had a
panel field, a DTO field, a payload key — and no reader.

## Two definitions offering the same thing

`user_definition_processes` (all four operations) and `users_list` / `users_create` /
`users_update` / `users_delete` (one each) both described the same API. Routing picked
whichever, and a goal that needed two operations was stuck the moment it landed on a
single-purpose one: `users_list` has no `id` input, so no delete could ever be planned from
it. The loop re-listed until it ran out of steps.

Invisible while a tool is pinned by hand, which is how it was being tested. Left free, it
appeared immediately.

The four were removed. Note that `runs.definition_id` is `ON DELETE CASCADE` — deleting a
definition takes its run history with it.

## A parameter that is accepted and never used

`McpServerClient.routePrompt` took an `arguments` map and never put it in the body. Every
caller passed it correctly; it was dropped between the signature and the JSON, and the
receiving service quietly fell back to guessing. See [15](15-carrying-a-value.md).

Nothing errors, nothing logs, and the behaviour is *almost* right — which is what made it
survive. Wire-level tests catch this class; call-level ones cannot.

## Turkish spelling reaches the database

`Yiğit` and `Yigit` are different strings, and a search for one returns nothing for the
other. There is no fault anywhere in the stack — but "the delete did not happen" and "the
search found nobody" look identical from a console that reports the first and not the
second. See the empty-answer rule in [15](15-carrying-a-value.md).

## Deleting a test resource does not delete the copy

Maven copies `src/test/resources` into `target/test-classes`. Removing the source file
leaves the copy in place and on the classpath, so a fixture you have already deleted goes on
breaking the build. Two runs were spent on a file that was no longer there.

`./mvnw clean` or `rm target/test-classes/<file>`. The same shape as the week-old process
above: something that is gone can still be in effect.

## A file named application.yaml under src/test/resources shadows the main one

Not merged with it — replaced. For an ordinary service that costs a few defaults; for
`mcp-config` it removed the line telling the server to read plain files instead of cloning a
git repository, and it went looking for a URI it has never had.

Test-only properties belong on the test class, in `@SpringBootTest(properties = {...})`,
where they add to the configuration rather than standing in for it.

## A masking pattern that skipped the line it mattered most on

Writing `.env.example` templates from the real files meant blanking anything whose name said
password, secret, token or key. The pattern was `^([A-Z_]+)=`.

`MCP_CIPHER_KEY_V1` has a digit in it. It did not match, so the line was copied through
untouched — the key that opens every sealed value in the database, written into a file
sitting next to a README.

Caught by looking for that variable in the output and finding it in neither list: not
blanked, not kept. A line a filter never saw appears in no report it writes.

**Count what a masking script skipped, not what it caught.** The dangerous line is the one
the pattern did not match, and that line is invisible by construction. Afterwards, scan the
result for the thing you were removing rather than trusting the removal:

```sh
grep -hE "^[A-Za-z_0-9]+=.+" *.env.example | grep -iE "password|secret|token|key"
```

## 127.0.0.1 means something different in a container

A default of `127.0.0.1` is correct while the six services share a host and points a
container at itself the moment they do not. It cost three separate faults the first time
the stack ran under compose — the MCP server's address, the cipher's, and nothing else
working until both were named as services.

The same shape catches a shared secret that has a different variable name at each end:
`MCP_SERVER_TOKEN` on one side, `PUBLISHER_TOKEN` on the other. Nothing is wrong with
either until somebody has to set both, and then it is a `401` from a service that is up
and answering.

**Two variables that must match are two chances to set only one of them.** Feed both from
one value where you can.

## A config server's overrides reach every client

`mcp-config` serves an `overrides` block to *every* application, which is written in its
own configuration and is easy to read past. Routing an admin password through it to reach
the gateway would have handed the same password to the panel.

A secret goes to the one service that needs it, even when that means passing it outside
the mechanism everything else uses.
