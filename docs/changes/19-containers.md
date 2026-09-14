# 19 — Running it as containers

Six services in six repositories, four languages, and no way to start them but six
terminals and a remembered order. This is the compose file that replaces that, and the
things that only broke once the services stopped being local processes.

## The shape

```
postgres ─┬─ liquibase ──────────────┐
redis  ───┤                          │
rabbitmq ─┘                          │
                                     ▼
          mcp-config ──► mcp-cipher, mcp-gateway, mcp-server, mcp-action, mcp-panel
```

**mcp-config first, and healthy before anything else starts.** Not a preference: every
service fetches its settings from it at start up, and one that starts while it is down
falls back to local defaults *silently*. That is the failure this ordering exists to
prevent, and it is the same reason the restart matrix in [00](00-the-stack.md) says the
same thing about local processes.

**The schema is applied by a container that runs once and exits.** The gateway waits for
it to succeed. The application does no DDL and runs with `ddl-auto: none`, so a schema
that was never applied does not refuse to start — it turns up later as a query error.

**Build contexts come from `.env`.** The sources are in six directories; a compose file
that hard-coded them would work on one machine.

**Infrastructure is not published to the host.** Postgres, Redis and the broker are
reachable inside the network and nowhere else. Something is usually already on 5432, and
a database reachable from outside is a database somebody else can reach.

## What only breaks in a network

Three of the four faults found here are the same fault wearing different clothes: an
address that is correct for a process on a laptop and wrong for one in a container.

**`127.0.0.1` is the container itself.** The gateway looked for the MCP server there, and
`MCP_CIPHER_ADDRESS` had it too. Both are right when the six services share a host; both
point a container at itself when they do not. They name services now.

**A shared secret with two names.** The gateway sends `MCP_SERVER_TOKEN`; the MCP server
checks `PUBLISHER_TOKEN`. Nothing was wrong with either — they had simply never been set
from one place before, because whoever ran the stack locally exported both by hand. The
symptom was a `401` from a service that was up and answering.

One value in `.env` feeds both now. **Two variables that must match are two chances to set
only one of them.**

**A secret routed to everyone.** The first version of the admin bootstrap passed
`MCP_ADMIN_PASSWORD` through mcp-config. That works, and it also hands the password to the
panel: the config server's overrides reach *every* application, which is written in its own
configuration and was read too late. It goes straight to the gateway now.

## The fourth: a build that looked broken

`mcp-action` would not build:

```
dial tcp: lookup storage.googleapis.com: no such host
```

Go's default proxy serves module archives from there, and a network that blocks it
produces a message that reads like a broken build rather than a blocked one. Two builds
were spent looking at the Dockerfile.

`GOPROXY=direct` fetches from each module's own origin and gets through. It is a build
argument rather than the default: it is slower, and it needs `git` in the build image.

## First-run access

A freshly installed stack had no way in. Registering through the panel gives a `VIEWER` —
right for the second person and wrong for the first, who then has to reach past the
application into the database to grant themselves the role. **A setup step that ends in
"now run this UPDATE" is a setup step that is not finished.**

`MCP_ADMIN_EMAIL` and `MCP_ADMIN_PASSWORD` create that account at start up, **only into an
empty users table**. Not "if this email is missing": that would let anyone who can edit a
compose file add an administrator to a running system, and a compose file is easier to edit
than a database. Once any account exists this does nothing, whatever the variables say.

The password has the same floor as the registration form. A bootstrap is not a way around
the rule.

### A transaction that wanted a database

The first version carried `@Transactional`, and fifteen context-loading tests failed. A
transaction opens on method entry — which means a connection — so every test that started
a Spring context needed a database in order to create an administrator it was never going
to create.

It is gone. `count()` and `save()` are each atomic, and the window between them only
matters if two gateways start against an empty database at the same instant, where the
unique index on email decides.

## Fetching the sources

Six repositories in six directories, and a compose file whose build contexts come from
`.env`. `clone.sh` fetches them and writes that file, pointed at wherever they landed.

Optional: somebody who already has the sources sets `MCP_*_PATH` and never runs it. What
it saves is six `git clone` lines and the chance of mistyping one.

Three things it will not do, and each is the reason a setup script gets run twice rather
than once:

- **Pulls with `--ff-only`.** Its job is to fetch code, not to decide what to do about
  somebody's local commits. A merge it started and could not finish would leave a working
  tree in a state nobody asked for.
- **Skips a directory that exists and is not a repository**, rather than writing into it.
- **Never touches an existing `.env`.** That file holds passwords. A setup script that
  overwrites credentials is one nobody runs twice — and the second run is exactly when it
  is needed, because the first one is when you find out what is missing.

## Images

| Service | Base | Note |
|---|---|---|
| mcp-gateway, mcp-config | JRE | Already had Dockerfiles |
| mcp-cipher, mcp-action | distroless/static | A shell here would be a shell next to the keys |
| mcp-server | python:slim | Dependencies in their own layer, runs as a non-root user |
| mcp-panel | node:alpine | `output: "standalone"` |

Next's standalone output traces what the server actually imports instead of carrying all
594 MB of `node_modules` into the image. It changes nothing for `next dev`.

There is no `public/` to copy — the favicon and the icon live under `app/`, through Next's
file conventions. The first Dockerfile assumed otherwise and failed on it.

## Verified by

Against a stack brought up from nothing, because none of this is provable from the source.

The first pass found the four faults above and fixed them. The second was the real test:
an empty directory, `mcp-starter` cloned **from GitHub rather than from the working copy**,
then `./clone.sh`, then the credentials, then `docker compose up -d`. What was tested is
what somebody else would download.

Eleven steps, and this time nothing needed fixing:

| | |
|---|---|
| `clone.sh` | six repositories, `.env` written with their paths |
| Containers | nine up, the three infrastructure ones healthy |
| Administrator | created from `.env`, logs in on the first attempt |
| Panel | `/login` answers |
| MCP server | `status: ok` |
| Catalogue | published from the gateway, token accepted |
| Model record | saved with its API key sealed |
| Definition | created, `published: 1` |
| Tool call | planned → queued → executor → `succeeded` |
| Result | written back sealed under key `v1` |
| Logs | five services writing into the shared directory |
| Restart | "an account already exists", one user |

One thing had to be set by hand: `GOPROXY=direct`, because this network blocks the host
Go's default proxy serves archives from. It is in the README's known limits, and reading it
there is how it got set — which is the only evidence that section is worth having.
