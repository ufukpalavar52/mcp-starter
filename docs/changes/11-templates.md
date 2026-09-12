# 11 — Placeholders in a REST action

## They work in the URL, and always did

`{{key}}` is substituted in the URL, in header values and in the body. A definition can be
written as `https://api.internal/v1/users/{{id}}` and the id comes out of the sentence:

```
"42 numarali kaynagi getir"  →  arguments {"id": "42"}  →  GET .../v1/users/42
```

That part needed nothing. What did not work was everything around it.

## An optional filter was refusing the whole plan

A listing endpoint with four optional filters could not be used at all:

```
?search={{search}}&first_name={{first_name}}&last_name={{last_name}}&email={{email}}
→ Template refers to undefined input(s): email, first_name, last_name, search
```

The inputs **were** defined — declared, optional, with empty defaults. `build_values` only
puts a key in when something supplies it, and `render` leaves an unfilled placeholder
untouched, so `find_unresolved` refused the plan rather than let a literal `{{search}}`
reach the executor.

That refusal was right in general and wrong here. **A query string is a list of filters, and
a filter with no value is not an empty filter — it is one nobody asked for.** So
`render_url` drops the whole parameter:

| Given | Becomes |
|---|---|
| nothing filled | `/api/users` |
| only `first_name` | `/api/users?first_name=ali` |
| `?page={{page}}&limit=50` with no page | `/api/users?limit=50` |

The path is deliberately untouched. `/users/{{id}}` with no id stays a problem — dropping it
would silently turn "delete user 13" into "delete users", which is a different request
against a different resource.

`render_body` does the same for a JSON body: a field whose value is one unfilled
placeholder is dropped, so a PUT changing one field sends that field. A body that is not
JSON is left entirely alone — this cannot tell a field from a line of text, and guessing
would be editing somebody's payload on a hunch.

## Two problems shared one sentence

"Template refers to undefined input(s): email" was said about an input plainly listed in the
editor, which sends the reader looking for a typo that is not there. They are different
problems needing different actions:

| Situation | Now says |
|---|---|
| `{{x}}` in the template, no such input | `Template refers to undefined input(s): x` |
| the input exists, nothing supplied a value | `No value for input(s): x. They are declared but nothing supplied one…` |

## A GET could never be saved once it had a body

A new REST action starts as POST with a body. Switching it to GET greys the body field
out — and the gateway refuses a GET carrying one. With the field disabled there was no way
to clear it, so the definition could not be saved again, and the panel showed only
`Request violates domain rules` with the reason buried in the response's `details`.

Fixed in two places, and both were needed: choosing GET now clears the body, and the body
is dropped again when the definition is saved. The second is what rescues definitions
already in that state.

## Verified by

`test_api.py` — unfilled filters drop out rather than refusing the plan, a filter that was
given is kept, a missing path placeholder is still a problem, a parameter with a value
beside the placeholder is left alone, a JSON field nobody filled is dropped, a body that is
not JSON is untouched, and the two messages are told apart.

`definition-mapping.test.ts` — the body of a GET is dropped on the way out, every other
method keeps its own.
