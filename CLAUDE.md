# CLAUDE.md

## Project

- Call `source .env` before running mix.
- Work on `main`. Pushing `main` deploys nothing. `just deploy staging` deploys the current branch to the staging server; `just deploy production` tags a release from `main`.
- When a commit finishes or changes a Backlog task, update the task's status (and `quick` label) in the same commit.

## Coding Standards

- Do not add comments that reiterate what the code does.
- Only comment on code if the intent is non-obvious or complex.
- Do not leave dead code or commented-out blocks.
- I don't mind more lines of code if future-me understands it more easily.
- Optimise for readability and maintainability rather than blindly pursing DRY.

## Agent skills

### Issue tracker

Backlog.md tasks under `backlog/`, managed with the `backlog` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical status strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root (created lazily when needed). See `docs/agents/domain.md`.
