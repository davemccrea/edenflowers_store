# Eden Flowers

## Development

### First-time setup

```bash
git config core.hooksPath .githooks
brew install just
```

`.githooks/pre-commit` formats staged Elixir (`mix format`) and JS/CSS (Prettier via `npx`). `pre-push` runs `mix precommit`.

The server commands (`just sync-images`, `logs`, `console`) connect through these aliases in `~/.ssh/config`. Server IPs stay out of this public repo; the origin is behind Cloudflare.

```
Host edenflowers-staging
    HostName <staging IP>
    User <you>

Host edenflowers-production
    HostName <production IP>
    User <you>
```

### Commands

Run `just` to list everything. Each recipe wraps a script in `scripts/`, which you can also run directly.

```bash
just dev                        # dev server at localhost:4000, with .env loaded
just reset-local-db             # drop, set up and seed dev + test databases
just deploy staging             # push current branch to staging
just deploy production [0.3.0]  # tag a release from main (prompts for version if omitted)
just sync-images [staging|production] # sync images/ to servers (both if omitted)
just logs staging               # tail app logs on a server
just console production         # remote IEx on a server
```

`just deploy production` checks the tree is clean, `main` matches origin, and `mix precommit` passes, then bumps `mix.exs`, tags `vX.Y.Z` and pushes. GitHub Actions builds the image and deploys. Pushes to the `staging` branch deploy the same way.

`images/` is gitignored, so photos reach the servers only through `just sync-images`, which `just deploy` runs for its target before pushing. It mirrors with `--delete`: anything removed locally is removed on the server too.

### Database

- `mix ash_postgres.generate_migrations NAME` — generate migrations
- `./scripts/regen-schema.sh` — drop the database, delete all migrations and resource snapshots, regenerate them from the Ash resources, and re-seed. For breaking schema changes before there's production data to migrate.

### Translations

- `mix gettext.extract` — extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext` — update all locale-specific .po files

### Papra expense capture

Upload a document to [Papra](https://papra.app) and tag it `receipt`. That fires a webhook to `/webhook/papra`, and the app sends the document to Claude to extract the expense. Needs `PAPRA_BASE_URL`, `PAPRA_API_KEY`, `PAPRA_WEBHOOK_SECRET` and `ANTHROPIC_API_KEY` in `.env`.

### Stripe webhooks in dev

Order finalization and the confirmation email depend on `payment_intent.succeeded`. Run `stripe listen --forward-to localhost:4000/webhook/stripe` and set the `whsec_...` it prints as `STRIPE_WEBHOOK_SECRET`.

### Worktrees

[worktrunk](https://worktrunk.dev) manages parallel worktrees. Hooks in `.config/wt.toml` copy `deps/` and `_build/`, give each worktree its own database and port in `.env`, and seed it. `just dev` then works as normal.

```bash
wt switch --create feature/my-feature
wt list
wt remove
```

## Deployment

Servers are provisioned by [phoenix-ansible](https://github.com/davemccrea/phoenix-ansible). Deploys run via `.github/workflows/deploy.yml`. See [Commands](#commands).

## Maintenance mode

`MAINTENANCE_MODE=true` redirects all visitors to `/maternity`. To preview the site anyway, set `MAINTENANCE_BYPASS_SECRET` and visit any URL with `?preview=<secret>`; a session cookie keeps the bypass for later requests.
