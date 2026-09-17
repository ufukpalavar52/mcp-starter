# 23 — Who may run what

Authorisation was the role and nothing else. Anybody holding `DEVELOPER` could run every
published tool — including the one carrying `allowedCommands: ["*"]` with sudo, against a
fleet of servers. There was no way to say "this person may run the read-only diagnostics
and not the one that writes files".

A definition now says who may reach it.

## The mode is explicit, and that is the whole design

A definition is `OPEN` — anybody signed in may run it — or `RESTRICTED`, meaning the people
named on it and nobody else.

The obvious alternative is to skip the mode and let an empty list mean everybody. It reads
the same on a screen and is quietly much worse: **removing the last person from a restricted
definition would reopen it to the entire installation, and nothing visible would change.**

So a restricted definition with nobody on it is closed. That is a state somebody arrived at
deliberately, not an accident waiting for the last row to be deleted.

Every existing definition became `OPEN`, so adding this changed nothing about who could do
what on the day it landed.

## Two permissions, and one implies the other

`can_run` and `can_edit`, per person.

**Editing carries running with it.** Somebody who may rewrite the command may obviously run
the command they wrote; keeping the two apart would describe a restriction that does not
exist. The panel's checkboxes say so — ticking edit ticks run, clearing run clears edit —
rather than leaving somebody to discover that the server disagrees with the screen.

**`OPEN` means open to run, not to edit.** If the role alone were enough to edit, the only
way to protect a definition from being rewritten would be to restrict who can run it, which
are two questions with one answer between them. Editing always needs a grant; the role
check on the controller still applies on top of it.

The migration hands existing `DEVELOPER`s that grant on existing definitions, so nobody lost
something they had that morning.

**Granting is an administrator's act.** Somebody who may edit a definition can already
change what it does, but deciding who *else* gets to is a different kind of decision — left
with the role, anybody holding it could hand themselves what they were not given.

## An administrator is never shut out

Deliberate, and worth writing down rather than discovering: the alternative is an
administrator who restricts a definition, leaves themselves off it, and can only get back in
through the database. **A permission system whose recovery path is `psql` is one that gets
worked around.**

## Seven places, because the one that is missed is the one that matters

Listings and single reads, every write, execute, approve, and the run history. Reads answer
*not found* rather than *forbidden*: to somebody with no access, a tool they may not reach
and one that does not exist are the same fact, and telling them apart turns a refusal into
an inventory.

Approval is checked again at the moment it is given. A proposal can wait days, and access
can be taken away in between — the moment the command runs is the moment that has to be
permitted.

## The prompt path is enforced by not offering the tool

This is the part that is easy to get wrong.

With `execute` set, the MCP server plans **and dispatches inside one call**. By the time a
tool name comes back to the gateway, the job may already be on the broker — so a check after
routing cannot stop work that has already started.

So the gateway sends the names the caller may run, and the router only chooses among those.
The check that follows is an alarm, not a lock: it logs at error and says a bug rather than
a permission, because reaching it means the list was not honoured.

Empty means *no restriction*, not *nothing*. An administrator is sent no list at all, and a
list that meant both would offer them an empty catalogue. Somebody whose every tool is
restricted is told the catalogue is empty — true from where they stand, and saying nothing
about what exists.

## What stayed out

**The MCP server's own surface.** Its catalogue still carries every definition. Whether
another MCP client should reach it is a separate question with a separate answer, and
opening it here would have meant deciding it by accident. Enforcement is on the panel and
console path.

## Verified by

| | |
|---|---|
| `OPEN` | runnable by anybody |
| `RESTRICTED`, named | runnable |
| `RESTRICTED`, not named | not found, on every one of the seven |
| `RESTRICTED`, nobody named | closed, not open |
| `can_edit` | counts as `can_run` |
| Administrator | reaches everything, always |
| Deleting a shared secret's definition | the other definitions keep working |
