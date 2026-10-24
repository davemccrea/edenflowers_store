# CLAUDE.md

## Project

- Call `source .env` before running mix.
- After the initial prompt, ask "Shall I create a worktree for this session?". A worktree is optional. If yes, use `wt switch --create <branch> --no-cd` (Worktrunk) to create it, then move the session into it with `EnterWorktree({path: <worktree path>})`. Don't work in it by `cd` or absolute paths from main: the session stays rooted in main and the status bar shows main's dev server link instead of the worktree's. `.config/wt.toml` gives each worktree its own `.env`, port and seeded database. When the session's work is done, land it with `wt merge` from inside the worktree: it squashes, rebases onto `main`, fast-forwards (no merge commit) and removes the worktree, which also drops its databases and stops its imgproxy. Use `--no-squash` to keep a bigger branch's separate commits. Never `--no-ff` or a plain `git merge`. If the rebase conflicts on Ash migrations or snapshots, regenerate them rather than hand-resolving. To abandon a worktree without merging, use `wt remove`.
- Start the dev server with `just dev`, never `mix phx.server`: only `just dev` starts the local imgproxy and points `IMGPROXY_PREFIX` at it, so uploaded photos show.
- When giving a worktree's dev server URL, use its `PHX_HOST` and `PORT` from the worktree's `.env`, e.g. `http://faq-sidebar-52s.localhost:16381/en/faq`, never `http://localhost:16381/en/faq`. The plain localhost URL shares cookies with main and other worktrees.
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
- Email copy: after changing an email template or its translations, run `mix print_emails` (or `mix print_emails sv fi en`) and review the rendered text in every language. A new email or wording variant needs a scenario in `Edenflowers.Email.Previews`. For when each email is sent, follow `docs/agents/email-map.md`; `just map-emails` runs it and writes the map and every email to `tmp/emails.md`.
