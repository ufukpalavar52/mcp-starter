# 05 — Guardrails

Everything here applies to commands a **model** wrote. An operator's own template
is trusted differently, and where that matters it is said.

## The separator check

Requested directly: a generated command may not chain, pipe, redirect or
substitute. Everything after such a mark is a second command the allowlist never
saw.

```
SHELL_METACHARACTERS = (";", "&&", "||", "|", "`", "$(", "\n", ">", "<")
```

## A wildcard allowlist

"Everything except the blocked ones" had no way to be expressed, and an empty list
means nothing rather than everything. `*` says it. What it turns off is the prefix
gate and nothing else: the blocklist still applies, and so does the separator
check — permitting any single command does not permit three.

It also raises a warning on every run, not once at configuration time. Somebody
reading a command a week later cannot tell whether it was one of a handful an
operator chose or anything the model felt like, and those are different facts.

## Chains are cut rather than refused

The model wrote chains anyway. "apache kur ve calistir" is one goal and two
commands, and `install && start` is the obvious way to write it; the instruction
was already in the prompt and the retry with the refusal in hand produced the same
chain often enough that neither could be the whole answer.

Refusing the pair lost the install as well as the start. So `first_command()` cuts
where the model already put the boundary, keeps the first command, and reports the
rest as a `first_command_only` warning. The goal loop asks for the remainder once
this one has run.

Only sequencing marks are cut on — `&&`, `||`, `;`, newline. A pipeline is one
command in two halves: `cat access.log` without its `| grep 500` does something
else entirely.

### And then it produced a broken command

```
echo '#!/usr/bin/python3
```

The model had written a heredoc-ish `echo '…' > /tmp/x.py`, and the splitter
treated the newline **inside the quotes** as a boundary. The remaining half had an
unterminated quote, which bash answered with `unexpected EOF while looking for
matching '`. Worse: the half it kept no longer had the `>` in it, so a command the
guardrails would have refused went through instead.

The splitter is quote-aware now: it tracks single quotes, double quotes and
backslash escapes, and only cuts on marks **outside** them. Quoting that never
closes is not cut at all — a command nobody can parse is not one to take half of.

## Writing files

With `>` blocked for model-authored commands, "create a file with this content"
could not be expressed at all. The scan is the wrong rule for a body of text:
what makes a body safe is not the absence of a semicolon but that there is no
command syntax in scope where it lands.

So a new input type — **`block`** — is exempt from the metacharacter scan and held
to a narrower rule instead. The command must place it in a **quoted** heredoc,
where the shell expands nothing, and the value may not contain the terminator that
would close it:

```
cat > {{path}} <<'MCPEOF'
{{content}}
MCPEOF
```

Inside those two conditions there is no command syntax the value can reach — a
stronger statement than "we did not find a semicolon".

`textarea` was deliberately **not** reused. It means a bigger box in the panel and
nothing more, and exempting every definition that already used one would have
changed what those definitions permit without anybody asking.

Every other substituted value is still scanned. A path is a word, and a word
carrying a semicolon is a second command however careful the block beside it is.

## Invented filters

A definition whose action was called "Yeni sorgu" and whose purpose was "Bireysel
yaani db" was asked how many accounts there were. The model wrote
`where domain = 'bireysel'` — a filter nobody asked for, against a column that
happened to exist. It answered 0 where the answer was 585, and reported success.

Two things came out of that. The planner's prompt marks context as "naming, not
instruction". And `unrequested_filters()` reports, per run, any literal that
appears in neither the sentence, nor the arguments, nor what the operator wrote
about the action.

## Verified by

`test_guardrails.py` — the three gates, the wildcard, the blocklist surviving it,
and the text-block rules: a body allowed where a word would not be, an unquoted
heredoc refused, a body that would close its own block refused, and the other
inputs still scanned.

`test_planner.py` — a chain is cut and the rest reported, a newline inside quotes
is not a boundary, unterminated quoting is left alone, and what was cut is still
checked like any other command.
