# Logs — Loki, Grafana, Alloy

A place for the six services' logs to go, and something to read them with.

| Service | Image | Address |
|---|---|---|
| Loki | `grafana/loki:3.7.2` | http://127.0.0.1:3100 |
| Grafana | `grafana/grafana:13.2.1` | http://127.0.0.1:3000 |
| Alloy | `grafana/alloy:v1.19.2` | http://127.0.0.1:12345 (UI), 4317/4318 (OTLP) |

Every port is bound to `127.0.0.1`. Loki has no authentication in front of it, so on a
shared network this would be production output available to anybody who asks.

## Starting it

```sh
cp .env.example .env          # set MCP_LOG_DIR
docker compose up -d
```

Grafana opens on http://127.0.0.1:3000 with the Loki datasource already provisioned — sign
in and go straight to **Explore**. The credentials are whatever `.env` says; the defaults
are `admin` / `admin` and should not survive contact with anything but a laptop.

## Getting logs in

Two routes. Neither excludes the other.

### 1. Write files, let Alloy tail them

The default, and it needs no change to any service. Point `MCP_LOG_DIR` at the directory
they write to:

```
MCP_LOG_DIR=/Users/you/logs
```

Alloy picks up `*.log` directly inside it and one level down, and labels each stream by the
file's name:

```
/Users/you/logs/mcp-gateway.log   →   {service_name="mcp-gateway"}
/Users/you/logs/mcp-server.log    →   {service_name="mcp-server"}
```

Narrow the pattern with `MCP_LOG_GLOB` when the directory holds more than this stack's
logs. Pointing `MCP_LOG_DIR` at `/tmp` with the default `*.log` collects every unrelated
`.log` anybody's tooling has left there; `MCP_LOG_GLOB=mcp-*.log` takes the six and leaves
the rest.

It is mounted read-only. A log shipper with write access to what it is reading is a way to
lose the evidence.

### Nothing writes a file on its own

Worth knowing before expecting this to work: **none of the six services is configured to
log to a file.** Spring Boot, uvicorn, the Go binaries and `next dev` all write to stdout.
Files exist only where something redirected them:

```sh
./mvnw -B spring-boot:run       > ~/mcp-logs/mcp-gateway.log 2>&1 &
uvicorn app.main:app            > ~/mcp-logs/mcp-server.log  2>&1 &
```

Started from an IDE, they write to its console and Loki sees nothing. Two ways out: keep
redirecting, or give each service a file appender of its own — `logging.file.name` for the
Spring services, a `FileHandler` for Python, a redirect for the Go ones. The second
survives however they are started.

### 2. Push straight to Loki

For a service that already has an appender for it. Nothing in this stack has to change.

**Spring Boot** (`mcp-gateway`, `mcp-config`) — `loki-logback-appender`, pointed at
`http://127.0.0.1:3100/loki/api/v1/push`.

**Python** (`mcp-server`) — a `logging` handler for Loki, same URL.

**Go** (`mcp-action`, `mcp-cipher`) — these write to stdout; redirecting to a file under
`MCP_LOG_DIR` is less work than adding a client.

Anything speaking OTLP can send to Alloy on 4317 (gRPC) or 4318 (HTTP) instead.

## Asking questions of it

```logql
{service_name="mcp-gateway"}                          everything from one service
{service_name=~"mcp-.+", level="ERROR"}               every error in the stack
{service_name="mcp-server"} |= "PROBE"                lines containing a word
{service_name="mcp-gateway"} | json | status >= 500   if the service logs JSON
```

`level` is a label, parsed from the line, so filtering by it is cheap. Everything else is a
line filter — also fast, but it reads the lines rather than skipping streams.

## What is labelled, and what is not

`service_name`, `level` and `source` are labels. Nothing else is, on purpose.

Every distinct combination of labels is a separate stream in Loki. A label that varies per
line — a request id, a run ref, a user — multiplies the streams until queries crawl. Those
belong **in** the line, where `|=` and `| json` can still find them.

## Choices worth knowing about

**Alloy, not Promtail.** Promtail reached end of life in early 2026 and takes no further
fixes. Alloy does the same file tailing.

**The level is normalised.** The regex matches case-insensitively and the six services
between them wrote `ERROR`, `Error` and `error` — three separate labels, so `level="ERROR"`
answered with a third of the errors and said nothing about the rest. A filter that silently
returns some of the matches is worse than one that returns none. It is upper-cased, and
`WARNING` is folded into `WARN`.

**Multi-line events are joined.** A Java stack trace is one event written across forty
lines. Without joining, each arrives as its own entry, interleaved with whatever else was
logging, and the trace is unreadable exactly when somebody needs it. A new entry is one
starting with a timestamp; anything else is a continuation.

**No write-ahead log in Alloy.** The `wal` block is experimental and turning it on means
running the whole process with `--stability.level=experimental` — a large switch for a small
guarantee. The cost: if Alloy is killed between reading a line and delivering it, that line
is lost. Its position file records what was read, not what arrived. A Loki restart on its
own is fine — Alloy retries.

**Thirty days, then deleted.** `retention_period` in `loki/loki-config.yaml`, applied by the
compactor. A retention period without a compactor to enforce it is a setting that reads as a
promise and deletes nothing.

**Loki has no healthcheck.** Its image is distroless — no shell, no `wget`, no `curl` — so
there is nothing inside it to run one with. A `test:` line there fails forever and holds
back everything that waits on it, which is exactly what happened on the first `up`. Check it
from outside instead: `curl -s localhost:3100/ready`.

**Anonymous access is off.** It is the convenient choice for a local stack and the one that
becomes an open dashboard the first time this file is copied somewhere with an address.

## What this does not do

- **Nothing is collected from containers.** The infrastructure containers (postgres,
  rabbitmq, redis) log to Docker's own driver, not to a file here. Adding them means
  `loki.source.docker` and mounting the Docker socket — a bigger surface, and not what this
  was for.
- **No dashboards.** Explore answers the questions this is for. A dashboard is worth
  building once you know which four queries you keep retyping.
- **No alerting.** Loki's ruler is configured with somewhere to keep rules and no rules in
  it.
- **No metrics or traces.** Logs only. Alloy can carry all three, so this is a starting
  point rather than a limit.
