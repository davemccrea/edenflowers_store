# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to what they are in this repo's tracker (Backlog.md). Four of them are task statuses. `wontfix` is an archive.

| Label in mattpocock/skills | In our tracker                                  | Meaning                                  |
| -------------------------- | ----------------------------------------------- | ---------------------------------------- |
| `needs-triage`             | status `needs-triage`                           | Undecided: whether to do it, or how      |
| `needs-info`               | status `needs-info`                             | Waiting on reporter for more information |
| `ready-for-agent`          | status `ready-for-agent`                        | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | status `ready-for-human`                        | Decided, but only a human can do it      |
| `wontfix`                  | label `wontfix`, status `done`, then archived   | Will not be actioned                     |

`in-progress` and `done` are statuses as well. Work moves through them after triage.

To mark a task wontfix: `backlog task edit <id> -s done -l wontfix --comment "<why>" --comment-author @claude`, then `backlog task archive <id>`.
