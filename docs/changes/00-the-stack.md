# 00 — The stack

Six services across four project roots. Nothing after this file reads properly
without knowing where each job lives, so it comes first.

| Service | Language | Port | Job |
|---|---|---|---|
| `mcp-config` | Java | 8888 | Central configuration; everyone reads it at start up |
| `mcp-cipher` | Go | 9090 | Sealing; the one process holding keys, over gRPC |
| `mcp-gateway` | Java | 8080 | Owns the data, the REST API, and writes down results |
| `mcp-server` | Python | 8000 | The MCP surface; routes, plans, applies the guardrails |
| `mcp-action` | Go | — | The executor; takes jobs off the queue and does SSH/DB/REST |
| `mcp-panel` | TypeScript | 3111 | This application — the control plane's face |

Infrastructure runs in containers: postgres 5432, rabbitmq 5672, redis 6379.

## What happens to a prompt

```
panel ──prompt──▶ gateway ──▶ mcp-server
                                 │  router:    which tool?
                                 │  planner:   which command or query?
                                 │  guardrails: may this run?
                                 ▼
                            mcp.actions queue
                                 │
                                 ▼
                            mcp-action ──SSH/SQL──▶ the server
                                 │
                    mcp.results ◀┘   (and mcp.progress, when following)
                                 │
                                 ▼
                            gateway: seals it, writes it down
                                 │
                                 ▼
                            panel: polls and reads
```

Three properties of that split matter, and most of the later files rest on them:

- **Deciding happens in mcp-server.** Which tool is called, what command gets
  written, and whether that command is allowed.
- **Running happens in mcp-action, which checks the guardrails again.** There is
  a broker in between; anything able to publish to the queue could otherwise
  present a command that was never checked at all.
- **The data lives in the gateway.** mcp-action has no database credentials and
  no reason to hold any.

## Restart matrix

| Changed | Restart |
|---|---|
| panel component, i18n, styles | nothing — `next dev` reloads |
| Python code or prompt text | mcp-server (it runs without `--reload`) |
| Java code | that service |
| `config-repo/*.yml` | the client that reads it |
| `mcp-config/.env` | mcp-config, then every client |
| a database migration | gateway |

Order matters: mcp-config first. Everything else reads its settings at start up,
and a service that starts while the config server is down falls back to local
defaults **silently** — which is the hardest kind of fault to diagnose.

## Where their output goes

All six write a log file into `MCP_LOG_DIR` (`~/mcp-logs` by default) as well as to the
console, and Loki collects them — see [18](18-logs.md). One thing to know when reading them
together: a service restarted while its log file has been deleted keeps writing to the
handle it already has, so the lines go nowhere and the file never reappears. Restart it
after recreating the directory, not before.

## What each service needs before it starts

`mcp-starter/env/` holds one `.env.example` per service, with every secret blank and the
addresses, ports and usernames real. They say what has to be filled in; they are not the
working files, which stay in each repository.

`CONFIG_USER` / `CONFIG_PASSWORD` appear in all six. Every service authenticates to
mcp-config with them, and mcp-config refuses to start without a password — deliberately,
since it hands out the database password, the JWT key and the broker password.

`MCP_CIPHER_KEY_V1` is the one that cannot be replaced. It exists only in the mcp-cipher
process and reaches neither the config server nor the database, which is what makes a copy
of the database not a copy of the data. Lose it and everything sealed with it is unreadable
for good.
