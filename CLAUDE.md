# CLAUDE.md

## Project

- Call `source .env` before running mix.
- Work on `main`. Pushing `main` deploys nothing. `just deploy staging` deploys the current branch to the staging server; `just deploy production` tags a release from `main`.
- Before touching the production database directly (psql, rpc writes, data fixes) or deploying production, run `just db-backup production` and confirm the dump landed in `tmp/`. `just deploy production` does this itself. To undo, `just rollback production <previous tag> <dump>` restores that dump and runs that tag's image (leave out the dump to keep the data).
- When a commit finishes or changes a Backlog task, update the task's status (and `quick` label) in the same commit.

## Coding Standards

- Only comment when the intent is non-obvious or complex. Never restate what the code does.
- Do not leave dead code or commented-out blocks.
- Optimise for readability and maintainability over DRY. More lines are fine if future-me understands them more easily.

## Agent skills

- Issue tracker: Backlog.md tasks under `backlog/`, managed with the `backlog` CLI. See `docs/agents/issue-tracker.md`.
- Triage: status strings and the `wontfix` label. See `docs/agents/triage-labels.md`.
- Domain docs: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
