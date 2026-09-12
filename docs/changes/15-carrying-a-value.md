# 15 — Carrying a value between steps

"Find the Yigits and delete them" is two steps, and the second one needs two things only
the first one knows: **which record**, and **what to do to it**. This file is about how
those travel, and the separate places one or the other was being lost, weakened, invented,
or declared finished early on the way.

Two symptoms, months apart in feel and a week apart in fact. An approval card offering

```
DELETE http://127.0.0.1:5500/api/users/1
```

for a search that had returned 59, 69, 86 and 97 — and later, a goal that deleted exactly
one of three and then stopped without saying anything.

The last two sections are the second symptom. One of them is a defect I introduced fixing
the first, which is the reason they are filed together.

## Asking a model for a sentence, when what was needed was a value

The step planner was asked to write the next request in words, and the words were then
routed like any other prompt. Asked what to do next, it answered:

> "For each user found, delete them one by one. First, delete user with id 59."

The value is in there. Getting it out meant routing reading a sentence written by another
model — and what came back, over four runs, was an empty field twice, that whole sentence
once, and the number `1` once.

So the step planner now returns the value too. `_Step` carries `values`, and the loop hands
them to the plan as arguments. The model still decides *whether* to go on; it no longer has
to encode the answer in prose for another model to parse back out.

## A value that was never in the answer

The first guard was that the value must **appear** in the answers it was supposedly read
from. That is no guard at all for a short one: `"1"` occurs in any body long enough to have
a digit in it, and the delete above passed it cleanly.

Now the value must be the value **of a field of that name**:

```
answers : {"count":4,"data":[{"id":59},{"id":69},{"id":86},{"id":97}]}
"id" is : 59, 69, 86, 97
1       : refused
```

Two more things are refused with it. A value under a name the tool does not declare — asked
for `id`, this model has answered under `user_id`, a plausible name for a field that does
not exist, which substituted into nothing and left the real input empty without saying so.
And a value that is the sentence: `{"id": "For each user found, delete them one by one…"}`,
which rendered into a URL nobody meant to call.

## The question never needed a model

If the step is waiting on `id` and the previous answer has an `id` field, that is a lookup,
not a judgement. It is now read directly out of the answers, and the model's own value is
kept only when it is one of them — it read the same answers and may have had a reason to
pick a later row.

When it is read rather than given, the step says so:

> processing the next one *(read from the previous answer: id=37)*

That line exists because of a run where the reason said `id 59` and the command said
`/users/37`. The search had come back unfiltered, so "the first row" was a stranger. Nothing
ran — it was held for approval — but **an approval screen whose sentence describes a
different record than its command is the worst way for one to be wrong.**

## The value never left the gateway

With all of that in place the delete still arrived with no id. The step planner was reading
`59` correctly; the gateway was sending nothing.

`McpServerClient.routePrompt` accepted an `arguments` parameter and never put it in the
request body. The parameter was there, every caller passed it correctly, and it was dropped
between the signature and the JSON.

Nothing failed. The MCP server simply received a step with no values and fell back to
recovering them from the sentence — which is where `id: 1` came from.

Found by measuring rather than reading. Three temporary log lines, at three hops:

```
router : wanted='id'  answers=368  values={'id': '59'}    ← read correctly
api    : unattended=True  body.args={}                     ← arrived empty
```

The gap between those two lines is the whole defect.

**A parameter that is accepted and unused fails silently.** The test for it asserts on the
wire, not on the call, because every caller was already correct.

## Routing does not get to fill a step nobody typed

Last piece. When a person writes the sentence, routing reading values out of it is the whole
point — "delete user 13" has the 13 in it. When the loop writes it, there is nothing in
there to read: *"Processing the first user found with first_name 'Yigit'"* contains no id.
Asked anyway, the model produced one and explained that an earlier search had returned a
user with that id. It had not.

An unattended step now runs on what the loop read out of the answers and nothing else. Where
that is empty the plan says the input is missing — true, visible, and harmless next to a
number that came from nowhere.

## A search that matched nothing is an answer

Typed `Yiğit`, where the records read `Yigit`:

```
search=Yiğit → {"count":0,"data":[]}
search=Yigit → [59, 69, 86, 97]
```

Nothing was found, so nothing should have been deleted — but the goal proposed the delete
anyway, with the id left as `{{id}}`, and the guardrails refused it. What the operator saw
was a failed DELETE rather than "nobody by that name".

A step waiting on an input the answers cannot supply now ends the goal and says so. **An
unfillable write is not a step waiting for approval; it is a step that cannot exist.**

## Fields from one record, not from wherever they appear

Filling only the input a plan recorded as waiting left the step after an approved delete
with no id — no deferral had been recorded for it. So the fill was widened to every input
the tool declares, read out of the answers.

Read one at a time, each from wherever it first appeared in the text:

```
args = {"id": "86", "last_name": "Yilmaz", "email": "yigit.yilmaz69@example.com"}
```

The `id` is 86's. The surname and the email are 69's — the record that had just been
deleted. **No such person exists.** Substituted into a search that took all three, it
matched nothing, the goal decided it was done, and two of the three Yigits were still
there.

Now one record is chosen first, and the fields are read only from inside it. The model's own
value picks it when there is one: it read the same answers and said which row it meant —
"the second user found" is a choice, not a phrasing. Without a record to anchor on, only the
one input actually being waited for is filled; filling the rest from the answers at large is
precisely what mixed two people together.

Finding the record is brace-counting rather than parsing, because the answers are trimmed to
a few hundred characters and the last one is routinely cut in half. A record that runs off
the end of the text is still one record's worth.

## A step that named a record and no operation

With the value right, the chain still stopped. The loop's second step read:

> "Processing the second user found with first_name 'Yigit'."

Which action does that need? The selection was shown that sentence and nothing else, and out
of *list / create / update / delete* it chose the listing — reasonably, since the sentence
asks for no operation at all. The delete never came.

The verb was in the goal, one hop away: *"ismi Yigit olan kullanıcıları bulup **siler**
misin?"*. The selection now sees what has been asked in the conversation — the questions
only, not the statements they became, because what is missing from a machine-written step is
the operation somebody typed. Oldest first, so the goal is at the top rather than buried
under the steps it produced.

This is the same shape as [16](16-approving-a-command.md): a decision that had already been
made was being made again, from less information than the first time.

## "Done", said while holding the record that is left

Three users named Gizem, two approvals, and a goal that stopped. What the loop logged:

```
Goal 302 is met after 3 step(s): Two users named 'Gizem' have been deleted so far;
the third one (id 96) also needs to be deleted to fully meet the goal.
```

`done: true`, and a reason saying the opposite in the same breath — with `{"id": "96"}`
handed over beside it. Replayed against the same steps, twice in three runs.

This is the failure the deferral mechanism was built for, and deferrals had quietly stopped
being recorded: they are written when the plan sets an action aside, and once the selection
began choosing one action at a time there was nothing to set aside. The same disappearance
had already made an indicator inert in [17](17-saying-what-is-happening.md); here it removed
the guard against a model losing count.

Which records have been acted on is not a judgement. The statements are right there:

```
GET    /api/users?first_name=Gizem   →  43, 70, 96
DELETE /api/users/43
DELETE /api/users/70                     96 appears in no statement
```

A field only counts as an identifier if it is already being used as one — **some** of its
values in the statements and **some** not. Every row has `first_name` Gizem and the search
statement names it, so nothing is outstanding there; no statement names an `email` at all,
so that column says nothing about what is left; `id` has two of three spent, so the third
stands out.

The leftovers are computed, but whether they matter is not decided here. "Find them and
delete the first" leaves rows untouched on purpose, and a rule that chased every unhandled
row would turn that into a different goal. So a leftover only counts when the model's own
answer names it — in its values, its request, or its reason — while claiming to be finished.
**We do not decide the goal is unfinished; we refuse a verdict the same answer contradicts.**

The replacement request is written here rather than taken from the model, because a model
that has decided it is finished words its request as a report — "the users named Gizem have
been deleted" — and routing that produces a listing.

Ten runs against the live stack: six with one record outstanding, all six continued; four
with every record deleted, all four stopped. Then end to end from the panel's own path —
three records, three approvals, three deletes, and a loop that stopped on its own.

## What the answer reports

One consequence worth noting: the prompt response's `arguments` used to be what routing
found in the sentence. Once a step could arrive with values already read out of an answer,
those were two different things, and reporting the sentence's version described a plan that
had used something else. It now reports what the plan ran on — which is also what the
gateway keeps in order to re-plan an approval from it (see [16](16-approving-a-command.md)).

## Verified by

`test_planner.py` — `done_is_refused_when_the_answer_names_a_record_nothing_touched`,
`done_stands_once_every_record_has_been_acted_on`,
`a_goal_that_asked_for_one_is_not_turned_into_all_of_them`,
`a_field_nothing_acts_on_says_nothing_about_what_is_left`, `values_come_from_one_record`,
`without_a_record_only_the_waiting_input_is_filled`,
`a_waiting_action_is_asked_for_the_value_not_a_sentence`,
`a_value_that_is_not_in_the_answers_is_dropped`,
`a_value_that_is_not_a_field_of_that_name_is_dropped`,
`a_value_under_a_name_the_tool_does_not_have_is_dropped`,
`the_value_is_read_out_of_the_answers_when_none_was_given`,
`a_value_taken_from_the_answer_says_so`, `a_search_that_matched_nothing_ends_the_goal`,
`a_search_that_found_something_still_goes_on`.

`test_api.py` — `routing_does_not_get_to_fill_a_step_nobody_typed`,
`what_the_loop_read_is_used`, `routing_still_reads_a_sentence_a_person_wrote`,
`the_answer_reports_what_the_plan_ran_on`, `the_choice_is_told_what_was_asked_before`,
`what_was_asked_before_is_the_questions_oldest_first`, `nothing_asked_before_adds_nothing`.

`McpServerClientTest` — an argument reaches the request body, and nothing is sent when there
is nothing to send. Against a real socket: the client pins its own request factory, so
`MockRestServiceServer` never sees the request.
