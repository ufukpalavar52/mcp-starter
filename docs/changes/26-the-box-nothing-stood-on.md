# 26 — The box nothing stood on

A tool screen showed this, and it was all true at once:

> 🛡 Nothing is executed. The MCP server only decides what would happen; no executor
> exists to run the command yet.
>
> ⚠ This action requires approval.
>
> ⚠ Published to the executor queue

Three clicks on that screen ran `tail -f /var/log/messages` on a live host three times.

| run | approved by | duration | exit |
|---|---|---|---|
| 70 | — | 133 s | 0 |
| 71 | — | 127 s | 0 |
| 72 | — | 121 s | 0 |

`approved_by` and `approved_at` were null on all three. Nobody approved, because there was
nowhere to. The command ran anyway, for two minutes each, against `192.168.139.110`.

## The gate existed and was enforced — on one path

`_needs_approval` is real, and `POST /api/v1/prompts` has stood on it since the SSH action
did. The console honours it; there is a test class named after the day it started to.

`POST /api/v1/executions` — the tool screen, and any MCP client — went straight to the
dispatcher:

```python
plan = await request.app.state.planner.plan(definition, body.arguments)
dispatch = await request.app.state.dispatcher.dispatch(...)   # unconditional
```

So `requireApproval` was computed into the plan, travelled to the panel, was drawn on the
screen as "This action requires approval." — and then ignored by the code that dispatches.

Worth saying plainly, because it is the part that generalises: **an operator's setting that
is read, rendered and never enforced is more dangerous than one that does not exist.** A
missing feature is discovered the first time somebody looks for it. This one answered every
question correctly right up to the moment it mattered.

In the gateway the same flag has never been read at all: `ActionConfig.requireApproval` is
carried and copied, and `RunStatus.AWAITING_APPROVAL` is a value nothing assigns.

## Why the screen looked like a dry run

Because of a sentence that outlived its fact. In `create_execution`'s own docstring:

> handing it to an executor is a separate step, and today that step reports that no
> executor exists rather than pretending the work ran

and in the panel banner, in blue, under a shield:

> Nothing is executed … no executor exists to run the command yet.

Both were true when they were written. `mcp-action` shipped; neither was revisited. The
excuse stayed in the file while the thing it excused became real — and the screen kept
promising, in the colour of reassurance, that nothing would happen.

This is the fifth time in this project that the defect was a system saying the wrong thing
about itself — see [24](24-ways-in.md) and [25](25-nobody-was-listening.md). The first four
said *nothing happened* when nothing had. **This one said nothing happened while something
did, which is the direction that costs more than a diagnosis.**

## What changed

`create_execution` calls the same `_needs_approval` the prompt path calls. The same
function rather than a second reading of the same flag: two places deciding what approval
means is how they come to disagree.

Only a `planned` plan is gated. A rejected one carries no command, and the dispatcher's own
refusal says something more useful than asking approval for nothing.

An `ExecutionRequest` carries no agreement — the endpoint never had a way to express one —
so an action that needs approval cannot run from here at all, and the refusal says where it
can. That is the honest state rather than a limitation to paper over: this screen shows
what a tool would do, and a command whose operator asked for a person in the loop needs the
path that has one.

The banner now says the screen runs the tool for real, in **warning colours with a warning
mark** rather than blue under a shield, and the button reads "Run the tool" rather than
"Build the plan" — which described what it did before it dispatched.

## Deploying the fix exposed the next one

Restarting the MCP server to pick up the gate emptied its catalogue, and every call came
back:

> Unknown tool: rock_linux_logs. Publish the catalogue first.

That service holds its catalogue in memory and fetches nothing, which is deliberate and
written at the top of `catalogue.py`: the alternative is it holding gateway credentials and
reaching back. An empty catalogue at start up is the accepted price.

The price was being paid by a person. Nobody noticed the empty catalogue, so somebody
republished by hand — twice in one day.

The party that can fix it is the gateway. It owns the definitions, it already holds the
credentials, and it was being told the problem in plain words and passing them to the user.
So a 404 from a tool call now republishes the catalogue and asks once more.

**On the status, not the sentence.** A 404 for a tool this service published means the two
copies have diverged, whatever words came with it. Matching the message would tie the
gateway to a string in another repository that nobody would think to keep in step.

**Once.** If a fresh catalogue does not have the tool, the tool really is gone, and a second
attempt turns a clear answer into a loop.

The MCP server's design is untouched — it still fetches nothing and holds no credentials.
What changed is that the service which *can* recover now does, instead of forwarding the
instruction to a human.

That makes three of these in two days: an executor that retried a broker forever and never
re-read its configuration, an approval flag that was rendered and never enforced, and a
catalogue whose owner was told it was missing and did nothing. **The recurring shape is not
a missing capability — it is a component holding everything it needs to recover and not
asking.**

## Approving where you are standing

Closing the hole left the screen honest and inconvenient: an action that needed approval
could not be run from the tool screen at all, and the refusal said to go to the console.

The obvious request followed — could the approval be given up front? It cannot, and the
reason is worth keeping rather than working around. **Approval is of a command, not of an
intention.** Planning is not deterministic; a step once proposed as `systemctl start httpd`
was re-planned on the way to running and came back as an install, which is why `_matches`
exists at all. Agreeing before a plan exists is agreeing to whatever the model writes next.

What *can* be removed is the detour. The endpoint now accepts the same `expect` the prompt
path has always carried, so the flow is: ask, read the command, click approve. Two calls
and one decision, in the screen that asked.

The comparison is unchanged and is the whole guarantee — approve `tail -f /var/log/messages`
and a re-plan that comes back with anything else is refused, not run.

Skipped actions are left out of what gets sent back. They resolve to nothing, because there
was no point resolving what will not run, and including them would fail the comparison for
every definition with more than one action.

## What stayed out

**Making the gateway enforce it too.** The check belongs where the dispatch happens, and
that is here. A second enforcement in the gateway would be a second opinion about the same
flag, which is the shape of the original bug.

## Verified by

| | |
|---|---|
| action needs approval, direct execution | not dispatched, no `run_id` |
| the same, the plan | still returned — it is what would be approved |
| the refusal's wording | names the console |
| action without the box | dispatches exactly as before |
| a rejected plan | reaches the dispatcher, not the gate |
| a 404 for a published tool | catalogue republished, call retried once |
| still unknown afterwards | reported, not retried again |
| any other refusal | passed through, nothing republished |
| a call that works | nothing republished |
| the command shown, sent back | dispatched |
| a different command approved | refused, not run |
| a first ask, nothing approved | awaiting approval |
| the panel's first call | carries no approval |
| nothing waiting | no approve button |
