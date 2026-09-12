# 14 — Reading the answer

## A REST body is a table wearing a different coat

A database action returns rows and the panel draws a table from them. A REST action returns
a body — so a search for ninety-nine users read as a paragraph of JSON, while the same
answer from a query would have been a table.

Three shapes are recognised, and everything else is left as text:

| Body | Read as |
|---|---|
| `[{…}, {…}]` | the rows themselves |
| `{"count": 99, "data": [{…}]}` | the envelope opened — `data`, `items`, `results`, `records`, `content` |
| `{"id": 102, "first_name": "Mehmet"}` | one record, one row |
| `[1, 2, 3]` | text — one value with several parts, not several records |
| `{"data": […], "errors": […]}` | text — **two arrays are not chosen between** |
| anything not JSON | text |

The last two are the point. Deciding which of two arrays somebody's API meant would be
wrong about half the time, and **a wrong table is worse than honest JSON**: it omits half
the answer and looks complete.

REST only. A command that prints a JSON file is still a command whose output somebody wants
to read as a file — turning `cat config.json` into a table would hide the formatting they
were looking at.

## Where it is derived, and why that changed mid-way

The intention was to derive at read time, so what is stored stays exactly what the endpoint
said. It was written that way, and no rows came back.

The full body is never stored. The recorder trims it to four thousand characters before
sealing, and a JSON listing cut at four thousand characters is not JSON at all — there was
nothing to derive from.

So it happens at record time, from the body in hand, before the trim. The stored text is
still the excerpt and still says it was cut; the rows are complete up to their own cap.

The reasoning had been right and the data it needed was not there. Worth remembering as a
shape: *derive from what is kept, not from what passed through.*

## The answer itself is not replaced

A listing endpoint puts a count and its paging beside the rows. Drawing only the rows would
throw that away, so what came back sits one click below the table, folded.

## Copying a result

A copy button on a finished run, next to the outcome.

- Rows go as **tab separated** text with a header line — that is what a spreadsheet reads
  when it is pasted into; commas need quoting rules and arrive as one column in half the
  tools people actually use.
- A command's output is copied exactly as it printed. The point of copying a log is to have
  the log.
- **Only what succeeded.** A failed target's output is an error and half an answer; pasting
  it beside the real rows is how a number nobody can reproduce ends up in a slide.
- Empty cells are empty, not the word `NULL`. The table says NULL so a reader can tell it
  from an empty string; a spreadsheet cell should be empty, because that is what it means
  there.
- Host addresses are written above each block only when there is more than one.
- The clipboard can refuse — permission denied, a page on plain http — and it says so.
  Silence after pressing copy is how somebody pastes what they copied ten minutes ago.

## What is not done

Export to CSV, Excel, PDF or Word. The shape is now shared, so each of those is a renderer
over the same rows rather than a feature of its own — but before any of it is worth
building, the size limits have to be faced: the body is trimmed at four thousand characters
and the rows are capped at five hundred. **A truncated Excel file is an empty file that
looks full.**

And PDF or Word is not the same feature as CSV. Those are documents — layout, headings,
page breaks — and somebody asking for "PDF" usually means "a report", which needs a template
decision before any code.

## Verified by

`JsonRowsTest` — each recognised shape, an empty list as an answer, two arrays left alone,
an unfamiliar envelope name left alone, non-JSON left as text, and an enormous answer
capped.

`RunResultRecorderTest` — a REST answer is read as rows before it is trimmed, and a command
printing JSON is still text.

`results.test.ts` — rows as a spreadsheet will accept them, a command's output kept exactly,
empty cells, nested values flattened, failures left out, hosts labelled only when there are
several, and nothing to copy when nothing succeeded.
