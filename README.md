# Eden Flowers

## Setup

Needs Elixir and Erlang from `.tool-versions`, Postgres, Node, [OrbStack](https://orbstack.dev) running (for the dev imgproxy) and `~/.local/bin` on `PATH`. `.env` is gitignored: copy it from another checkout. `config/runtime.exs` raises on any variable it lacks.

```bash
git config core.hooksPath .githooks   # pre-commit checks formatting, pre-push runs mix precommit
brew install just
just install-typst                    # pinned Typst CLI for receipt PDFs; dev and test need it
mix setup
just seed-db
```

Expense capture (Papra, Fastmail) is in [docs/papra.md](docs/papra.md). Dev and worktrees use production Papra.

## Commands

`just` lists them all. Day to day:

```bash
just dev                # dev server on localhost:4000, local imgproxy on PORT+1
PORT=4010 just dev      # another port (also honoured by forward-stripe)
just test [args]
just format
just forward-stripe     # set the whsec_... it prints as STRIPE_WEBHOOK_SECRET
just reset-db           # drop and migrate dev + test, then seed-db
```

Order finalization and the confirmation email depend on Stripe's `payment_intent.succeeded`, so checkout needs `just forward-stripe` running.

Tidewave is enabled in development. Start `just dev` before opening Codex in this trusted project, then use `/mcp` to check the connection. `.codex/config.toml` points Codex at `http://localhost:4000/tidewave/mcp`; `.mcp.json` configures Claude Code. Restart the client's MCP connection after changing either file. If you run on another port, update its Tidewave URL; new `wt` worktrees configure both clients automatically.

Translations, including adding a language, follow [priv/gettext/README.md](priv/gettext/README.md). Preview emails with `mix print_emails` or `just map-emails`.

## Worktrees

[worktrunk](https://worktrunk.dev) manages parallel worktrees. `.config/wt.toml` copies gitignored files such as `deps/`, `.env` and `infra/.vault_pass` from the main checkout, gives the worktree its own database and port, and seeds it. `wt remove` drops its databases and stops its imgproxy.

```bash
wt switch --create feature/my-feature
wt remove
```

## Production

Deploys, rollbacks, photos, maintenance mode and the server are in [infra/README.md](infra/README.md). Pushing `main` deploys nothing: `just deploy` does.
