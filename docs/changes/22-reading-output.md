# 22 — Reading what came back

Command output was drawn in the page's own tertiary grey, in the same block a quoted
document would get. That is the wrong claim: a quotation is something being *cited*, and
this is the machine talking back. A dark ground says so without a caption.

The rest of this note is about where the colour stops, because that turned out to be the
only interesting decision in it.

## What was missing, rather than dull

**The exit code was not on the screen at all.** It was in the payload, and whether a
command had worked was left to be inferred from its output — which for `cat > file` is
nothing at all, and for a script that printed a friendly message on the way to failing is
worse than nothing. Green on zero, red otherwise, next to the host.

## Colour splits along what is knowable

**A command is known to be shell.** The panel wrote the template and the guardrails read it
as shell before letting it run, so naming its parts is a fact rather than a guess: the verb,
its flags, quoted text, paths, and the operators that redirect or chain.

The verb is painted separately from the rest. It is the one thing a person checks before
approving, and `cat` and `rm` occupy the same space on a screen while meaning very different
days.

**Output is whatever a program printed**, and almost nothing about it is knowable. So only
the things that are: numbers, quoted text, and the handful of words a program reaches for
when it is reporting trouble. Anything further would be inventing meaning and painting it
on — a colour that says something the text does not.

That asymmetry is the whole design. It is tempting to treat both blocks the same because
they look the same; they are not the same kind of thing at all.

## Three smaller decisions with reasons

**No ANSI parser.** Nothing stored has ever carried an escape sequence, because the tools
suppress their own colour when there is no TTY — which is every command that reaches here.
Colouring what cannot arrive would have been decoration with a parser underneath it. If a
command ever does arrive with escape codes, that is the moment to write one, and this
paragraph is the note explaining why there wasn't one before.

**Quoted text matches before anything inside it.** A path inside `'…'` is text. A matcher
that took paths first would break the quote in half and colour its two halves differently —
so the ordering is not a preference, it is the correctness.

**stderr keeps the ground and takes a red edge, not a red fill.** It is the same voice on a
different channel. A red block said "this is an error", which a command writing its progress
to stderr — which is most of them — turned into a lie. Its text is left unpainted:
highlighting every line of an error report highlights nothing.

**The ground does not follow the theme.** A terminal is dark in a light room too, and
switching it would make the same output look like two different kinds of thing depending on
who was reading it.

## What colour cost

Testing Library's text matcher reads an element's *direct* text children and ignores the
ones inside child elements. A highlighted command is nothing but child elements, so eleven
assertions stopped matching text that had not changed on screen at all.

They match on the block now (`tests/terminal.ts`). One of the eleven turned out not to be a
terminal in the first place — the model's own answer — and went back as it was, which is
the sort of thing a blanket find-and-replace hides rather than reveals.

**A presentation change that splits text across elements is a change to every test that
reads that text.** Worth expecting rather than discovering.

## Where it is

| | |
|---|---|
| `components/ui/Terminal.tsx` | The block itself, one component for all three kinds |
| `lib/ui/shell-highlight.tsx` | The two highlighters, and the palette in one `COLOUR` object |
| `tests/terminal.ts` | The matcher the split text needs |

Used by the console card, the run outcome, the tools run screen and the plan's actions —
the same block everywhere, so a command reads the same whichever screen it is on.
