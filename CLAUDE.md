# CLAUDE.md

## Project

- Call `source .env` before running mix.
- After the initial prompt, ask "Shall I create a worktree for this session?". A worktree is optional. If yes, use `wt switch --create <branch>` (Worktrunk), not the built-in worktree tool. `.config/wt.toml` gives each worktree its own `.env`, port and seeded database. When the session's work is done, land it with `wt merge` from inside the worktree: it squashes, rebases onto `main`, fast-forwards (no merge commit) and removes the worktree, which also drops its databases and stops its imgproxy. Use `--no-squash` to keep a bigger branch's separate commits. Never `--no-ff` or a plain `git merge`. If the rebase conflicts on Ash migrations or snapshots, regenerate them rather than hand-resolving. To abandon a worktree without merging, use `wt remove`.
- Start the dev server with `just dev`, never `mix phx.server`: only `just dev` starts the local imgproxy and points `IMGPROXY_PREFIX` at it, so uploaded photos show.
- Pushing `main` deploys nothing. `just deploy` tags a release from `main`.
- Before touching the production database directly (psql, rpc writes, data fixes) or deploying production, run `just backup` and confirm the dump landed in `tmp/`. `just deploy` does this itself. To undo, `just rollback <previous tag> <dump>` restores that dump and runs that tag's image (leave out the dump to keep the data).
- When a commit finishes or changes a Backlog task, update the task's status (and `quick` label) in the same commit.

## Coding Standards

- Only comment when the intent is non-obvious or complex. Never restate what the code does.
- Do not leave dead code or commented-out blocks.
- Optimise for readability and maintainability over DRY. More lines are fine if future-me understands them more easily.

## Agent skills

- Issue tracker: Backlog.md tasks under `backlog/`, managed with the `backlog` CLI. See `docs/agents/issue-tracker.md`. Ungrilled tasks stay `needs-triage`; never implement one until you've grilled the user on it (`grilling` skill).
- Triage: status strings and the `wontfix` label. See `docs/agents/triage-labels.md`.
- Domain docs: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
