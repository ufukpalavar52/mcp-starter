# MCP stack — documentation

Copies, gathered here from the four repositories they live in. The originals stay where
they are; these are for reading the whole thing in one place.

| Where | What |
|---|---|
| [`changes/`](changes/) | Why the system is the way it is — one file per area of work |
| [`PANEL.md`](PANEL.md) | The panel: routes, definitions, the console, localisation |
| [`database/`](database/) | The schema, its migrations, and the rules embedded in it |
| [`../observability/`](../observability/) | Loki, Grafana and Alloy — not a copy; the stack itself lives there |
| [`../env/`](../env/) | One `.env.example` per service, secrets blank |

## `changes/` — the reasoning

Nineteen notes. Each says **what was wrong, why it was solved that way, and how it was
verified**. Not a release list: `git log` already says what changed.

Start at [`changes/README.md`](changes/README.md), which indexes them. If you are chasing
one behaviour rather than reading through, these carry the most:

- [`13-unattended-writes.md`](changes/13-unattended-writes.md) — a delete that nobody
  approved, and where the decision moved to
- [`15-carrying-a-value.md`](changes/15-carrying-a-value.md) — getting an id and an
  operation from one step to the next, and the places they were lost
- [`10-traps.md`](changes/10-traps.md) — the operational traps that bit more than once
- [`18-logs.md`](changes/18-logs.md) — the log stack, and what was wrong on the way to it

## `database/` — the schema

| File | What it is |
|---|---|
| `schema.sql` | **Dumped from the running database**, 2026-09-11. The truth. |
| `DATABASE.md` | The commentary: what each table is for, and the business rules the schema enforces |
| `migrations/` | The Liquibase changelog, 001 through 026, in order |

Three things to know before using these.

**`schema.sql` here is a fresh dump, not the committed one.** The copy in `mcp-gateway/docs`
was last written on 1 September and is missing five columns that exist in the database:
`warnings`, `goal_turn_id`, `deferred`, `arguments` and `action_id`, all on
`conversation_turns`. That file is stale; this one was taken from the live schema with
`pg_dump --schema-only`. It contains definitions only — no rows, no credentials.

**`DATABASE.md` is in Turkish,** unlike everything else here, and it was last edited on
21 August. It describes the schema as it stood then: the four migrations after 023 are not
in it. What they added:

| Migration | Column | For |
|---|---|---|
| 024 | `conversation_turns.deferred` | An action the plan set aside and what it waits on |
| 025 | `conversation_turns.arguments` | The values a step was planned with, so approving replays them |
| 026 | `conversation_turns.action_id` | The action a step was planned as, for the same reason |

The reasoning for 024–026 is in [`changes/15`](changes/15-carrying-a-value.md) and
[`changes/16`](changes/16-approving-a-command.md); the migration files themselves carry it
too, in their comments.

**Migrations 024 to 026 were applied by hand** with `psql`, not by Liquibase. They are
written as Liquibase formatted SQL and will be picked up on a fresh database, but the
existing one has no changelog row for them. Anyone running Liquibase against that database
should check `databasechangelog` before assuming it is in step.

## What is not here

The source. Four repositories, unchanged:

| Service | Path |
|---|---|
| `mcp-panel` | `~/WebstormProjects/mcp-panel` |
| `mcp-gateway`, `mcp-config` | `~/Documents/turkcell/` |
| `mcp-server` | `~/PycharmProjects/mcp-server` |
| `mcp-action`, `mcp-cipher` | `~/GolandProjects/` |

These copies do not update themselves. When a change note is written or a migration is
added, it is added in its own repository first; this directory is a snapshot taken on
2026-09-11.
