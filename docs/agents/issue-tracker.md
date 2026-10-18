# Issue tracker: Backlog.md

Issues and specs live as Backlog.md tasks under `backlog/`. Change them through the `backlog` CLI, not by hand-editing files. The CLI keeps IDs, frontmatter and section markers consistent. Pass `--plain` to read output. `backlog instructions overview` explains the CLI in general; where it disagrees with this file, this file wins.

Install the CLI with `npm i -g backlog.md`. `backlog browser` serves a local board at http://127.0.0.1:6420.

## Conventions

- One feature is one **parent task**. Its description is the spec, opening with a one-line summary of what the feature does for the shop
- A spec is one deliverable with a finish line: something true once it's done that isn't true now. A theme ("tidy the checkout code", "remove unused machinery") is not a spec. Each piece of work under a theme is a spec of its own
- Each implementation ticket is a **subtask** of the feature: `backlog task create "<title>" -p TASK-N`. Subtasks number themselves `TASK-N.1`, `TASK-N.2`, … Never combine several tickets into one task
- A subtask is a step toward its parent's goal and makes little sense without it. If it would read fine to someone who never saw the parent, or could ship alone with nothing gained by the others, make it a spec instead
- The CLI can't change a task's parent. To promote a subtask, recreate it as a top-level task, comment "Moved to TASK-N" on the old one and archive it
- Every description has a `**Why:**` line near the top: one or two sentences on why the work is worth doing, in terms of the shop, Jennie, customers or whoever reads the code next. A parent puts it right after its summary line; a subtask opens with it
- Put the problem, what to build and any decisions in the description (`-d`). Put each acceptance criterion in its own `--ac`
- Set the ticket type with `--type` (`feature`, `bug`, `refactor`, `chore`, `task`, `research`, `prototype`, `grilling`)
- Set `--priority` on parent tasks to the feature's impact, judged from its `**Why:**` line. Subtasks don't get one. Pair it with `quick` to find cheap, high-impact work:
  - **high**: customers or Jennie notice it often, money or orders are at risk, or it unblocks other high work
  - **medium**: a real improvement people notice now and then, or a refactor that makes upcoming work easier
  - **low**: nice to have, rare edge cases, tidy-ups nobody will feel
- Label a task `quick` (`--add-label quick`) if it fits in one sitting with nothing left to decide. `backlog task list --plain -l quick` lists them
- Label each parent task with who feels it, read from its `**Why:**` line: `customers` (shoppers notice it), `jennie` (her admin, time or money) or `developers` (only whoever works on the code). Use both `customers` and `jennie` when both feel it. Subtasks don't get one
- Blocking tickets go in `--dep TASK-N.M` (comma-separated). Don't write a "Blocked by" section
- Status is the task's `status` field, one of the triage strings in `triage-labels.md` plus `in-progress` and `done`. It is the only record of status, so keep it current as work lands: `backlog task edit TASK-N.M -s <status>`
- Comments and conversation history go in as task comments: `backlog task edit TASK-N.M --comment "<text>" --comment-author @claude`
- Implementation plans go in `--plan`. Notes made while working go in `--notes`. Check off acceptance criteria with `--check-ac <n>`
- `backlog board` or `backlog task list --plain` lists open work by status
- Refer to tasks by ID (`TASK-18.5`), not by file path
- When every subtask is `done` (or archived as `wontfix`), set the parent to `done`. Never archive `done` tasks; they stay in the Done column
- When something is still undecided (whether to do it, or how), set it to `needs-triage` and say what's open in the description. When it's decided but only the human can do it (a check on a real device or in a dashboard), set it to `ready-for-human` and add a comment saying what's left

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
