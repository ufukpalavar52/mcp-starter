# mcp-starter

Everything needed to stand the stack up, and the reasoning behind how it is built.

| Where | What |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | The whole stack: infrastructure, the schema, the six services |
| [`env/`](env/) | One environment template per service, for running them outside Docker |
| [`observability/`](observability/) | Loki, Grafana and Alloy — where the logs go |
| [`docs/`](docs/) | Why things are the way they are, and the database schema |

## Starting it

The sources live in six repositories. Clone them wherever you like — the defaults
assume they sit beside this one:

```sh
git clone https://github.com/ufukpalavar52/mcp-gateway.git
git clone https://github.com/ufukpalavar52/mcp-config.git
git clone https://github.com/ufukpalavar52/mcp-server.git
git clone https://github.com/ufukpalavar52/mcp-action.git
git clone https://github.com/ufukpalavar52/mcp-cipher.git
git clone https://github.com/ufukpalavar52/mcp-panel.git
```

Then:

```sh
cp .env.example .env     # fill in every blank — see below
docker compose up -d
```

The panel opens on http://localhost:3000. Create an account through `/register`; the
first user arrives as a `viewer` and has to be made `admin` in the database before it
can write:

```sh
docker compose exec postgres psql -U mcp -d mcp \
  -c "UPDATE users SET role = 'admin' WHERE email = 'you@example.com';"
```

### The values that have no default

`.env.example` leaves every credential blank on purpose: a stack that starts with a
blank password is a stack nobody notices is open. Compose refuses to start without
them, naming the one it wants.

```sh
openssl rand -base64 32      # JWT_SECRET_KEY, MCP_CIPHER_KEY_V1
```

**`MCP_CIPHER_KEY_V1` must decode to exactly 16, 24 or 32 bytes.** The command above
gives 32. Anything else and mcp-cipher refuses to start, saying so — which is how it
should be: a keyring that half works is worse than one that does not start.

**`ROUTER_API_KEY`** is the model that turns a sentence into a tool call. Without it the
console answers that no model is configured, and everything else still works.

## What starts, and in what order

```
postgres ─┬─ liquibase ──────────────┐
redis  ───┤                          │
rabbitmq ─┘                          │
                                     ▼
          mcp-config ──► mcp-cipher, mcp-gateway, mcp-server, mcp-action, mcp-panel
```

**mcp-config goes first, and the others wait for it to be healthy.** Every service
fetches its settings from it at start up, and one that starts while it is down falls
back to local defaults *silently* — the hardest kind of fault to find a week later.

**The schema is applied by Liquibase, in a container that runs once and exits.** The
gateway waits for it to succeed. The application performs no DDL of its own and runs
with `ddl-auto: none`, so a schema that was never applied turns up at run time as a
query error rather than at start up as a refusal.

**Infrastructure is not published to the host.** Postgres, Redis and the broker are
reachable inside the network and nowhere else; something is usually already on 5432,
and a database reachable from outside is a database somebody else can reach. Only the
panel, the gateway, the MCP server and RabbitMQ's management UI are bound — all to
`127.0.0.1`.

If a port is taken, `PANEL_PORT`, `GATEWAY_PORT`, `MCP_SERVER_PORT` and
`RABBITMQ_UI_PORT` are in `.env`.

## Logs

Every service writes to `MCP_LOG_DIR` (`./logs` by default) as well as to its container's
output. The observability stack reads that same directory:

```sh
cd observability && docker compose up -d
```

Grafana opens on http://localhost:3000 — which collides with the panel, so set
`PANEL_PORT` or change Grafana's. Details in
[`observability/README.md`](observability/README.md).

## Running the services outside Docker

For development, running them directly is faster than rebuilding an image on every
change. [`env/`](env/) has a template per service; the infrastructure can still come
from compose:

```sh
docker compose up -d postgres redis rabbitmq liquibase
```

Then start each service from its own repository. `env/README.md` says which file goes
where.

## Known limits

- **`docker compose build` needs a working `GOPROXY`.** mcp-action depends on
  `modernc.org/sqlite`, whose archives are served from `storage.googleapis.com`. On a
  network that blocks it the build fails at `go mod download`; everything else builds.
- **No image is published anywhere.** Every `up` builds from source. Pushing images to
  a registry would make a fresh machine faster, and would mean somewhere to push them.
- **One replica of each.** `mcp-action` can be scaled (`docker compose up -d --scale
  mcp-action=3`) because it is a queue worker; nothing else is written for it.
- **No backups.** The volumes hold the database, and nothing copies them anywhere.
