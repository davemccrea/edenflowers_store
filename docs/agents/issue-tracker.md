# Issue tracker: Backlog.md

Issues and specs live as Backlog.md tasks under `backlog/`. Change them through the `backlog` CLI, not by hand-editing files. The CLI keeps IDs, frontmatter and section markers consistent. Pass `--plain` to read output. `backlog instructions overview` explains the CLI in general; where it disagrees with this file, this file wins.

Install the CLI with `npm i -g backlog.md`. `backlog browser` serves a local board at http://127.0.0.1:6420.

## Conventions

- One feature is one **parent task**. Its description is the spec, opening with a one-line summary of what the feature does for the shop
- Each implementation ticket is a **subtask** of the feature: `backlog task create "<title>" -p TASK-N`. Subtasks number themselves `TASK-N.1`, `TASK-N.2`, … Never combine several tickets into one task
- Put the problem, what to build and any decisions in the description (`-d`). Put each acceptance criterion in its own `--ac`
- Set the ticket type with `--type` (`feature`, `bug`, `refactor`, `chore`, `task`, `research`, `prototype`, `grilling`)
- Blocking tickets go in `--dep TASK-N.M` (comma-separated). Don't write a "Blocked by" section
- Status is the task's `status` field, one of the triage strings in `triage-labels.md` plus `in-progress` and `done`. It is the only record of status, so keep it current as work lands: `backlog task edit TASK-N.M -s <status>`
- Comments and conversation history go in as task comments: `backlog task edit TASK-N.M --comment "<text>" --comment-author @claude`
- Implementation plans go in `--plan`. Notes made while working go in `--notes`. Check off acceptance criteria with `--check-ac <n>`
- `backlog board` or `backlog task list --plain` lists open work by status
- Refer to tasks by ID (`TASK-18.5`), not by file path
- When every subtask is `done` (or archived as `wontfix`), set the parent to `done` and archive the parent and its subtasks: `backlog task archive TASK-N.M`, then `backlog task archive TASK-N`. Archived tasks stay readable with `backlog task view`
- When only the human can finish a task (a decision, a check on a real device or in a dashboard), set it to `ready-for-human` and add a comment saying what's left

## When a skill says "publish to the issue tracker"

Create the parent task, then a subtask for each ticket, using `backlog task create`.

## When a skill says "fetch the relevant ticket"

Run `backlog task view TASK-N.M --plain`. The user will normally give you the task ID.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a parent task with one **child** subtask per ticket.

- **Map**: the parent task's description holds the Notes / Decisions-so-far / Fog body.
- **Child ticket**: a subtask of the map with the question in its description. `--type` records the ticket type (`research`/`prototype`/`grilling`/`task`).
- **Blocking**: the subtask's dependencies (`--dep`). A ticket is unblocked once every task it depends on is `done`.
- **Frontier**: open subtasks of the map that are unblocked and not `in-progress`. The lowest number goes first.
- **Claim**: `backlog task edit <id> -s in-progress` before doing any work.
- **Resolve**: write the answer with `--notes`, set `-s done`, then edit the map's description to add a context pointer (gist + task ID) under Decisions-so-far.
