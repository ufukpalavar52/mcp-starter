# Change notes

One file per area of work. Each says **what was wrong, why it was solved that way,
and how it was verified.**

Not a release list. `git log` already says what changed; what is written here is
the reasoning behind the decisions — the part somebody needs six months later
when they ask "why is it like this?", and that somebody is usually us.

## Contents

| # | File | Subject |
|---|---|---|
| 00 | [00-the-stack.md](00-the-stack.md) | Services, ports, where each job lives |
| 01 | [01-console-history.md](01-console-history.md) | Keeping the console's history, and sealing it |
| 02 | [02-router-and-config.md](02-router-and-config.md) | The routing model, central config, leaked secrets |
| 03 | [03-goal-loop.md](03-goal-loop.md) | Turning one prompt into several steps |
| 04 | [04-ssh.md](04-ssh.md) | Host keys, authentication, `sudo` |
| 05 | [05-guardrails.md](05-guardrails.md) | Command checks, chain splitting, writing files |
| 06 | [06-approval.md](06-approval.md) | Approval made real, `dryRun` removed |
| 07 | [07-output-and-streaming.md](07-output-and-streaming.md) | Making output visible, and following a log |
| 08 | [08-console-ui.md](08-console-ui.md) | Paging and search |
| 09 | [09-branding.md](09-branding.md) | The icon and the logo |
| 10 | [10-traps.md](10-traps.md) | Operational traps that bit more than once |
| 11 | [11-templates.md](11-templates.md) | Placeholders in a REST action |
| 12 | [12-several-actions.md](12-several-actions.md) | One definition, several actions |
| 13 | [13-unattended-writes.md](13-unattended-writes.md) | A delete that nobody approved |
| 14 | [14-reading-the-answer.md](14-reading-the-answer.md) | Results as rows, and copying them |
| 15 | [15-carrying-a-value.md](15-carrying-a-value.md) | Getting an id — and the verb — from one step to the next |
| 16 | [16-approving-a-command.md](16-approving-a-command.md) | Turning a step down, and approving the one shown |
| 17 | [17-saying-what-is-happening.md](17-saying-what-is-happening.md) | The wait before a card, and the delete dialog |
| 18 | [18-logs.md](18-logs.md) | Loki, and getting each service to write a file |

## Where the tests stand

| Repo | Tests |
|---|---|
| `mcp-server` | 257 |
| `mcp-gateway` | 120 (1 skipped) |
| `mcp-config` | 9 |
| `mcp-action` | every package passing |
| `mcp-cipher` | every package passing |
| `mcp-panel` | 82 |

Each file ends with the tests added for that work. When you wonder why a
behaviour is the way it is, read the test name first — they are named to carry
the reason, not just the assertion.
