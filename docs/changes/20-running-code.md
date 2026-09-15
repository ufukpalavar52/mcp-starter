# 20 — Writing code from a prompt and running it

Three things were wanted: write code from a sentence and run it on a server, send a file
and run that, and author shell directly. Most of the machinery was already here. What was
missing was smaller than it looked, and one thing that looked like a control turned out to
be pointing the wrong way.

## What already worked

| | |
|---|---|
| Shell authored by the model | `rock_linux`, with the allowlist, the blocklist and approval |
| Writing a file | `rock_linux_file` — a `block` input in a quoted heredoc |
| Chaining two actions | `planner.py:_defer_unfillable()`, the same path "find and delete" takes |

A `block` is the one input exempt from the shell-metacharacter scan, because a python
file with no newline in it is not a python file. What replaces the scan is narrower: the
command must place it in a *quoted* heredoc, where the shell expands nothing, and the
value may not contain the terminator. Nothing in it can end the command.

## The schema was the bottleneck, and it was built three times

`block` and `textarea` both reached a client as a plain `{"type": "string"}`. The panel
generates its run form from the schema and nothing else, so both were drawn as a one-line
field — and **a script cannot be pasted into a one-line field**. A definition built around
a heredoc could not be called from the panel that created it.

The fix is one `format: "textarea"` hint. Finding where to put it was the part worth
recording: the schema is built in **three** places.

| Where | Read by | State |
|---|---|---|
| `mcp-gateway` `InputType.jsonSchemaFormat()` | The panel | Live |
| `mcp-server` `models.py:_JSON_FORMATS` | Real MCP clients | Live |
| `mcp-panel` `lib/definitions.ts:toolInputSchema()` | Nobody | **Dead** |

mcp-server's own docstring warned about this — "the gateway builds the same schema for its
own panel, and shipping it separately would create two copies that can disagree" — and a
third copy had been written anyway, exported, never called, and already out of step with
the two that run. **A duplicate nothing calls does not stay correct; it stays unnoticed.**

The hint says nothing about the scan. `block` and `textarea` are drawn the same way and
governed differently, and which one skips the metacharacter scan is read from the input's
own type. A schema travels through a catalogue and any caller can write one, so it is no
place to keep a safety decision.

## A file is not an upload

Loading a script from a file needed no endpoint. The browser reads it, the text becomes
the field's value, and it travels the way a typed one does. A second path to the server
would be a second way in to guard, for a result the first one already reaches.

Text only, refused on a NUL byte — the test git uses, and the one that matters here, since
a heredoc cannot carry a NUL at all. Decoding has already replaced whatever else was not
UTF-8, so refusing on replacement characters too would turn away a latin-1 file that would
have been fine.

## One definition, because the loop cannot cross two

`rock_linux_script` holds all three: write, run, and a dynamic action for when arguments
or a pipe are needed. They are together because `Routed.tool_name` is fixed for the length
of a conversation — the goal loop moves between *actions*, never between tools.

Asked to write a python file and run it, the planner picks the first two, sets the third
aside with its reason, and resolves:

```
cat > /tmp/mcp-deneme.py <<'MCPEOF'
import socket
print(socket.gethostname())
MCPEOF

python3 /tmp/mcp-deneme.py
```

The model wrote the body and moved `interpreter` off its `bash` default to `python3` on
its own.

**It cannot be run from the Tools screen**, and that is deliberate upstream: a definition
with several actions called with arguments and no prose is refused — *"the request said
which in no words at all"*. Guessing is how a search once also deleted something. It is
used from the console, where there is a sentence.

`interpreter` is deliberately not required. A request that only writes a file must not be
made to name an interpreter it will never use.

## A block was bounded by nothing

Every other input is bounded by being a word. A block is copied into a command line, a
queue message and a shell's stdin, and **no component along that path declared a ceiling**
— so the first one to find the limit would have been whichever broke first, reporting its
own symptom rather than the cause.

256 KB now, refused in `mcp-server`'s guardrails because that is where every caller passes:
the panel, the console, and an MCP client nobody here wrote. The panel's own limit is a
courtesy to the person typing; **a cap enforced in a form is a cap on the people who use
the form.** Both schema builders publish it as `maxLength` so a client can refuse before
sending rather than after.

The reason names the input and its size, never its value. Printing it back would put a
quarter of a megabyte of somebody's script into a log line, an error banner and a stored
conversation turn.

## The blocklist points the wrong way, and was left alone

`blockedPatterns` are matched against the **resolved** command, which includes the
substituted heredoc body. So they read the script's contents:

| | |
|---|---|
| A comment saying `# rm -rf yapma` | **refused** |
| `print('reboot gerekmez')` | **refused** |
| `shutil.rmtree('/veri')` | **allowed** |

It refuses harmless mentions and permits actual destruction. Extending the list would add
false positives without closing anything — a script can delete a disk without containing
any of those five strings.

Left exactly as it is, by decision rather than by omission. Removing the body from the scan
would loosen a control and would change `rock_linux_file` too; the noise is visible and a
loosening would not be. What is worth saying plainly is that **for a tool whose purpose is
running arbitrary code, the blocklist is not the boundary — approval is.** All three
actions require it, and a person reads the resolved command before anything runs.

`allowedCommands: ["*"]` stays on the dynamic action for the same reason. It never meant
"anything": what is left is still one command, no chaining, no pipe, no redirection, no
substitution.

## What was not changed

`EXCERPT_LIMIT` stays at 4000 characters. A truncated output is marked as truncated, so it
never reads as a command that printed exactly that much — which is the property that
matters. Raising it would inflate every sealed row for a rare case, and a script with more
to say than that should write a file and be asked for it.

## Verified by

Against the running stack, at each boundary rather than only at the end.

| | |
|---|---|
| Gateway schema | `content` carries `format: "textarea"`, `path` does not |
| MCP server catalogue | the same, after publishing |
| Planner, no prose | refused, as designed |
| Planner, with a sentence | both actions planned, third set aside, commands resolved |
| Guardrail ceiling | at the limit allowed, one character over refused |
| Blocklist against bodies | the three cases in the table above |

Tests: 8 in the gateway, 12 in mcp-server, 7 in the panel.

The actual execution on the server was not run from here — it needs an approval, and the
approval belongs on the console screen where a person is looking at the command.
