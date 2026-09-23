# CLAUDE.md

## Project

- Call `source .env` before running mix.

## Coding Standards

- Do not add comments that reiterate what the code does.
- Only comment on code if the intent is non-obvious or complex.
- Do not leave dead code or commented-out blocks.
- I don't mind more lines of code if future-me understands it more easily.
- Optimise for readability and maintainability rather than blindly pursing DRY.

## Agent skills

### Issue tracker

Local Markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical status strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root (created lazily when needed). See `docs/agents/domain.md`.
