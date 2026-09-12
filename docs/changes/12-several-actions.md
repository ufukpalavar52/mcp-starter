# 12 — A definition with several actions

## What it used to mean

A definition's actions were a **sequence**: all of them ran, in order, and a failure stopped
the rest. The executor still says so:

> A failed step stops the sequence. Carrying on would run a step whose precondition is now
> unknown, which is worse than stopping.

That is a workflow. But a definition is also how somebody groups the operations on one
resource — list, create, update and delete against the same users API — and there the
actions are **alternatives**.

Asking that definition for "the users called mehmet" ran all four:

```
129  GET    /api/users?first_name=mehmet   200
130  POST   /api/users {"first_name":"mehmet"}   400
131  PUT    /api/users/0                    skipped
132  DELETE /api/users/0                    skipped
```

The last two were skipped only because the POST failed first. Had the API accepted a partial
body, a DELETE would have gone out.

## The request decides now

After routing picks the tool, the definition's own model is asked which of its actions the
request needs. What it does not ask for is set aside — kept in the plan so it can be seen,
never built into the job.

A definition with one action is not a choice and is never asked about.

Three rules hold it up:

- **A choice that could not be made runs nothing.** A model that failed to answer is not
  permission to run four writes.
- **A `tools/call` with arguments and no prose cannot choose.** There is no way to tell
  which of four operations was meant, and guessing all of them is how a search deletes
  something.
- **What was set aside stays in the plan.** Somebody reading a plan with one call in it has
  to be able to tell the other three were considered — a different fact from their not
  existing.

## Required became a per-action question

The field still lives on the definition; the check now asks only about the inputs the
**running** actions use, and the templates already say which action needs what.

This was the thing making a four-action definition impossible to declare honestly. `id` is
required by the delete and meaningless to the list, so requiring it blocked listing — which
is why every input had to be optional, and why nothing was ever checked.

## And an action can wait for an earlier one

"Find the user called Mehmet Bulut and delete them" needs both actions, and the second
cannot run yet: the id it deletes by is in the first one's answer, which does not exist at
planning time. Asked to choose, the model picks both — reasonably, the request does ask for
both — and the plan was then refused whole for an id nobody could have supplied.

So it is **deferred** rather than refused:

```
[will run]  GET    ?first_name=Mehmet&last_name=Bulut
[waiting]   DELETE → waiting on id, which an earlier action has to answer first
```

Only when something runs before it. An action nobody can fill with nothing preceding it is a
request with no target, and refusing that is the right answer.

## The plan was building from the wrong list

`build_job` iterated `definition.actions` rather than the plan, so everything set aside was
dispatched anyway and the whole feature bought nothing. The plan decides what runs now; the
definition is what the tool *can* do.

## Verified by

`test_api.py` — the others are set aside rather than run, a set-aside action is not built
into the job, required is asked of the actions being run and still demanded when that action
runs, a choice that could not be made runs nothing, a prose-less call cannot choose, one
action is never a choice, an action waiting on an earlier one is deferred, and one with
nothing before it is still refused.
