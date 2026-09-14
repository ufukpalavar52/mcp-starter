# mcp-starter

Everything needed to stand the stack up, and the reasoning behind how it is built.

| Where | What |
|---|---|
| [`docker-compose.yml`](docker-compose.yml) | The whole stack: infrastructure, the schema, the six services |
| [`clone.sh`](clone.sh) | Fetches the six repositories and writes a `.env` for them |
| [`env/`](env/) | One environment template per service, for running them outside Docker |
| [`observability/`](observability/) | Loki, Grafana and Alloy — where the logs go |
| [`docs/`](docs/) | Why things are the way they are, and the database schema |

## Starting it

The sources live in six repositories. `clone.sh` fetches them and writes a `.env`
pointing at wherever they landed:

```sh
./clone.sh                  # into the parent directory
./clone.sh ~/work/mcp       # or somewhere of your choosing
./clone.sh --ssh            # over SSH rather than HTTPS
```

It is optional — if you already have the sources, point `MCP_*_PATH` at them in `.env`
instead. Running it again updates what is there rather than re-cloning, leaves a
repository with local changes alone, and **never touches an existing `.env`**: that file
holds passwords, and a setup script that overwrites credentials is one nobody runs twice.

Then fill in the blanks it left — see below — and:

```sh
docker compose up -d
```

Doing it by hand instead:

```sh
git clone https://github.com/ufukpalavar52/mcp-gateway.git
# … and the other five, then:
cp .env.example .env
```

The panel opens on http://localhost:3000, and `MCP_ADMIN_EMAIL` /
`MCP_ADMIN_PASSWORD` from `.env` are what you log in with: the gateway creates that
account, once, when the users table is empty.

Everyone after that registers through `/register` and arrives as a `viewer`, which an
administrator raises from the Users page.

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

**`MCP_ADMIN_EMAIL` and `MCP_ADMIN_PASSWORD`** are the first administrator. The password
has the same floor as the registration form — 12 characters — and a shorter one creates
nothing and says so in the log. Leave both blank and the stack starts with no accounts
at all, which is right for an installation that manages its users elsewhere.

That account is created **only into an empty users table**. Not "if this email is
missing": that would let anyone who can edit a compose file add an administrator to a
running system.

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

## What was verified

The stack was brought up from nothing and taken through a full round trip:

| | |
|---|---|
| Nine containers | up, the three infrastructure ones healthy |
| The administrator | created from `.env`, logs in, holds `admin` |
| A model record | saved with its API key **sealed** through mcp-cipher |
| A definition | created, and the catalogue published to the MCP server |
| A tool call | planned, queued, run by the executor, `succeeded` |
| The result | written back sealed, under key `v1` |
| Logs | five services writing into the shared directory |

Three things were wrong and are fixed. Each was an address or a name that is right when
the services are local processes and wrong when they are containers: the gateway looked
for the MCP server on `127.0.0.1`, the cipher address was the same, and the shared
publish token has a different variable name at each end — `MCP_SERVER_TOKEN` on the
gateway, `PUBLISHER_TOKEN` on the MCP server. One value in `.env` now feeds both, because
two variables that must match are two chances to set only one of them.

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

- **On a network that blocks `storage.googleapis.com`, set `GOPROXY=direct` in `.env`.**
  The default Go proxy serves module archives from there, and the failure reads like a
  broken build rather than a blocked one. `direct` fetches from each module's own
  origin: slower, and it needs git in the build image, which is why it is not default.
- **No image is published anywhere.** Every `up` builds from source. Pushing images to
  a registry would make a fresh machine faster, and would mean somewhere to push them.
- **One replica of each.** `mcp-action` can be scaled (`docker compose up -d --scale
  mcp-action=3`) because it is a queue worker; nothing else is written for it.
- **No backups.** The volumes hold the database, and nothing copies them anywhere.
