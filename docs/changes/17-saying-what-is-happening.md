# 17 — Saying what is happening

Two places where the console was doing the right thing and telling nobody.

## Twenty seconds of nothing, then a card

A finished run is when the goal loop *starts* deciding, and deciding is a model call — on a
real goal the delete step appeared eleven seconds after the search returned. The console
polls for it (`ABSORB_ATTEMPTS × ABSORB_INTERVAL_MS`, eight tries at two and a half
seconds), and during that whole window it showed nothing at all. Then an approval card
appeared out of a clear sky.

> "işlemleri yaparken devam ettiğine dair bir ibare çıksın, birden approve butonu çıkıyor"

### The first attempt was inert

The signal chosen was `conversation_turns.deferred` — an action the plan set aside, cleared
when the loop takes it up. A turn with something left in it, the reasoning went, has a step
on its way.

It shipped, it was tested, and **it never appeared once.** The column stopped being written
the moment the selection began choosing one action at a time: with only the search chosen,
nothing is ever set aside.

```
deferred dolu tur sayisi: 0
```

That is worse than having done nothing. An indicator wired to a fact that is never true
looks like a feature that works, and the next person to look at the silence will believe it
has already been dealt with.

### Asking the thing that knows

The loop is the only component that knows it is deciding. It now says so directly —
`GoalProgress`, in memory beside `RunProgress` and for the same reason: this is true for a
few seconds and then it is not, and nothing here is a record.

The mark covers **both** model calls — deciding what comes next, and planning it. Clearing
after the first would put the indicator out several seconds before the card it was
announcing. It is cleared in a `finally`, and anything older than two minutes is forgotten,
so a loop that died between marking and clearing cannot leave a spinner nobody can dismiss.

```
 3s  continuing=false  turns=1  awaiting=0
 6s  continuing=true   turns=1  awaiting=0     ← the gap
 9s  continuing=true   turns=1  awaiting=0
12s  continuing=true   turns=1  awaiting=0
15s  continuing=false  turns=2  awaiting=1     ← the card
```

The line does appear briefly after an ordinary question too, because the loop is consulted
after every executed run and genuinely is deciding. That is honest. What must not happen is
the line outliving the decision, and that is what the tests hold.

## `window.confirm` cannot name what it is deleting

> "console kayıtları silinirken modal çıksın, js default ekranı hiç güzel durmuyor"

It looked wrong, and it also *was* wrong. The browser's dialog takes a string and nothing
else, so the question read "delete this conversation and the questions in it?" over a
sidebar of twenty rows — and which one "this" meant was whichever row the pointer had
happened to be over. It also blocks the whole page while it waits.

The replacement is a `CModal`, like every other dialog in the panel, and it names the
conversation:

```
┌─ Sohbeti sil ──────────────────────────────┐
│  en cok hesabi olan 3 domaini ver          │
│                                            │
│  İçindeki sorular da gider. Çalıştırma     │
│  kayıtları yerinde kalır; bu işlem geri    │
│  alınamaz.                                 │
│              [ Vazgeç ]  [ Sohbeti sil ]   │
└────────────────────────────────────────────┘
```

The state holds the whole conversation rather than its reference, because the question being
asked is "this one?" and answering it needs the title.

The wording moved with it. The question is now in the heading and in the name, so the line
below says what happens instead of asking again — including that it cannot be undone, which
the old string never mentioned.

## What to take from it

*Silence is a claim.* A console that shows nothing is saying "nothing is happening", and it
was saying that for eleven seconds while the loop worked.

*Derive the signal where the fact lives — and check that it is ever true.* The first attempt
picked a column that reads exactly right and had quietly stopped being written. The test
passed because the test supplied the value; nothing asked the database whether any row had
one. A single `count(*)` would have caught it before it shipped.

*A dialog whose only button is "yes" is not asking.* The same point as the approval card in
[16](16-approving-a-command.md), a week apart, in a different component.

## Verified by

`ConversationServiceTest` — `aConversationSaysWhenAStepIsBeingDecidedForIt`,
`aConversationNobodyIsDecidingForSaysSo`, `aDecisionThatWasSettledIsNoLongerClaimed`.

`ConsoleHistory.test.tsx` — "says so while the loop is still deciding"; "says nothing once
the loop has settled"; "asks before deleting a conversation, and names which one"; "deletes
only once the person says so"; "leaves the conversation alone when the answer is no".

And against the running stack, which is what the first attempt lacked: polled every three
seconds across the gap, the flag comes on after the run and goes off as the card lands.
