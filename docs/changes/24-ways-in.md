# 23 — Ways in, and code that worked while looking broken

Adding a user had no working path at all. The panel's invite window only closed itself —
its send button called nothing and its fields were bound to nothing — and open registration
had just been removed. The forgotten-password link pointed at `/login`. Somebody locked out
had nobody to ask but an administrator with `psql`.

This note is about the two ways in that now exist, and about six faults found on the way.
**Four of the six were not broken behaviour.** The code worked; the screen or the status
code said otherwise. That turned out to be the more interesting half.

## Two ways, and why they need each other

**An invitation** sends a link and the person chooses a password nobody else ever knows.

**A password an administrator sets** creates the account outright. It is marked as needing
to change: two people know it and only one owns the account, so the panel opens nothing
else until that is no longer true.

Mail is *required* for invitations — one that cannot be delivered is not created, because a
row the person it names will never hear about is worse than a refusal, and the refusal is
at least visible.

That is only defensible because of the second way. An administrator setting a password
needs nothing but the database, so a misconfigured SMTP host locks nobody out of their own
installation. **The two were built together and one of them is the reason the other can be
strict.**

## Forgetting a password

Answered the same whether the address has an account or not. Anything else and the login
page becomes a way of finding out which addresses are worth attacking — and it is open to
anybody who can reach it. The log keeps the distinction; the operator is allowed to know.

An hour, not an invitation's seven days: an invitation moves at the speed of hiring
somebody, a reset link is a password, and the less time it spends in a mailbox the better.
Single use. Expired, spent and never-issued are refused in the same words.

Using one ends every session of that account. Resetting because an account was taken, while
leaving whoever took it signed in, undoes the reason for resetting.

## The one that would have been worst

Injecting `JavaMailSender` directly stopped the gateway from starting at all without an
SMTP host — Spring only builds that bean when `spring.mail.host` is set.

Read that against the paragraph above: the escape hatch that needs no mail lives behind the
same application that would not boot. A misconfigured mail host would have locked somebody
out of the installation *and* out of the way back in.

Optional at wiring, required at use. **A dependency that is only needed for one feature must
not be able to stop the service that carries the alternative.**

## Four faults where nothing was broken

**A mistyped password logged you out.** A wrong current password answered `401`. The panel's
client reads `401` as an expired session: it refreshed the token, retried, got the same
answer and cleared the session. So mistyping a field signed you out of a perfectly valid
session — and then the login screen refused the new password, because it had never been
set. It answers `422` now. *Who are you* and *what did you type* are different questions and
need different answers.

**A sent mail reported a parser error.** The reset endpoint answered `202` with no body; the
client treated only `204` as empty and went straight to `json()`. The screen said
`Unexpected end of JSON input` while the mail was already on its way. Whether there is a
body is the honest test; which success code carried it is not. The endpoint says `204` too,
which is also the truthful code — nothing is queued.

**A toast outlived its session.** The queue is module state and the login screen draws no
toaster, so a message raised before signing out waited there invisibly and appeared after
the next sign-in. Somebody was told their password had been changed, on the screen they
reached after being signed out for failing to change it. The queue is emptied with the
session now.

**Two screens said untrue things.** The settings page carried a banner reading "nothing on
this page is connected" long after the password form was — which is a very good reason never
to try it. And the password rule demanded a digit and a symbol that nothing checks, while
the button sat disabled with no explanation of why.

## The pattern

Four of six faults were a true statement in the wrong place, or a true code with the wrong
meaning. None would have been caught by a test of the thing they described, because the
thing they described worked.

They were caught by somebody using it and saying *"it doesn't work"* — and being right about
the experience while wrong about the cause every single time. **"No output", "it logged me
out", "my new password doesn't work" and "it says JSON error" were four different symptoms
of code doing exactly what it was asked.**

Worth carrying forward: when a report does not match the code, the screen is a place to
look, not only the logic. A banner, a status code and a stale toast are all things the
system says about itself, and a system that says the wrong thing about itself is broken in
the way that matters.

## Smaller things, kept

A secret that another definition still references survives that definition's deletion.
Three of them shared one SSH key; deleting any took the key with it and the other two broke
at their next run. Sharing was never the mistake — the deletion was.

Sessions under settings were invented down to a city held in a translation string. A count
from Redis and a working "sign out everywhere" replace them — which ends the current session
too, since one that leaves the screen you pressed it on signed in has not done what it says.
No device and no place, because neither is recorded.

## Verified by

Unit tests at each layer, and four rounds against the running stack, since every one of the
four misleading faults was invisible from the source alone.

| | |
|---|---|
| Registration | `/auth/register` is gone, 404 |
| Invitation | created, mailed, accepted once, refused the second time |
| Administrator's password | account active, panel locked to the password screen |
| Forgotten password | same answer either way; link works once; sessions revoked |
| Wrong current password | refused without signing anybody out |
| Mail | delivered to a local catcher, in the panel's own colours |
