# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `issues/`.

## Conventions

- One feature per directory: `issues/<feature-slug>/`
- The spec is `issues/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `issues/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading
- The `Status:` lines are the only record of status; keep them current as work lands. `just issues` lists every open feature with its statuses
- Open features stay at the top level of `issues/` whatever their status. When every issue is `done` or `wontfix`, set the spec's `Status:` to match, move the directory into `issues/done/`, and fix any `issues/<feature-slug>/` paths that pointed at it
- When only the human can finish an issue (a decision, a check on a real device or in a dashboard), set it to `ready-for-human` and say what's left in its `## Comments`

## When a skill says "publish to the issue tracker"

Create a new file under `issues/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `issues/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `issues/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `issues/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
