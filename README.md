# Eden Flowers

## Development

### First-time setup

After cloning, point git at the project's hooks directory so the pre-commit and pre-push hooks run:

```bash
git config core.hooksPath .githooks
```

The hooks live in `.githooks/` (versioned with the repo). `pre-commit` formats staged Elixir files with `mix format` and staged JS/CSS files with Prettier (via `npx`). `pre-push` runs `mix precommit` (compile, deps.unlock, format check, tests). On the first commit that touches JS or CSS, `npx` will download Prettier into its cache; subsequent runs are instant.

### Running locally

- `iex -S mix phx.server` — start the server at [`localhost:4000`](http://localhost:4000)

### Papra expense capture

Expenses are captured via [Papra](https://papra.app), a document archiving service. Upload a document to Papra and tag it `receipt` — this fires a `document:tag:added` webhook to `/webhook/papra`. The app fetches the document, sends it to Claude for data extraction, and records the expense.

Four environment variables are needed. Add them to `.env`:

```bash
PAPRA_BASE_URL=https://app.papra.app   # or your self-hosted instance URL
PAPRA_API_KEY=...                       # API key from Papra account settings
PAPRA_WEBHOOK_SECRET=...               # signing secret shown in Papra webhook config
ANTHROPIC_API_KEY=...                  # Claude API key for receipt extraction
```

To test locally, expose the dev server with a tunnel (e.g. `ngrok http 4000`) and point the Papra webhook URL at `https://<tunnel-host>/webhook/papra`. Copy the signing secret from Papra into `PAPRA_WEBHOOK_SECRET`.

### Stripe webhooks in dev

Order finalization and the confirmation email both depend on `payment_intent.succeeded`. In a second terminal, run `stripe listen --forward-to localhost:4000/webhook/stripe` and export the `whsec_...` it prints as `STRIPE_WEBHOOK_SECRET`.

### Database

- `mix ash.setup` — create the database, run migrations, and seed
- `mix run priv/repo/seeds.exs` — seed the database
- `mix ash_postgres.generate_migrations NAME` — generate migrations

#### Regenerating migrations

When making breaking schema changes it's often easier to regenerate all migrations from scratch. `scripts/regen-schema.sh` automates this:

```bash
./scripts/regen-schema.sh
```

It drops the database, deletes all existing migrations and resource snapshots, regenerates them fresh from the current Ash resource definitions, and re-seeds the database.

### Translations

- `mix gettext.extract` — extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext` — update all locale-specific .po files

### Worktrees

The project uses [worktrunk](https://worktrunk.dev) to manage parallel worktrees. Each worktree gets its own Postgres database and a unique port, configured automatically via hooks in `.config/wt.toml`.

```bash
wt switch --create feature/my-feature  # create worktree, copy deps, create + seed db
wt list                                 # show all worktrees and their status
wt remove                               # remove current worktree
```

On creation, the hooks copy `deps/` and `_build/` from the main worktree (no recompile needed), append `DATABASE_NAME` and `PORT` to the worktree's `.env`, and create + seed a fresh database. To start the server in the new worktree:

```bash
source .env && iex -S mix phx.server
```

`DATABASE_NAME` and `PORT` are already set in `.env`, so no extra configuration is needed.

## Deployment

Server provisioning is handled by [phoenix-ansible](https://github.com/davemccrea/phoenix-ansible). App deploys run via GitHub Actions (`.github/workflows/deploy.yml`) to the server provisioned by that repo.

### Releasing a new version

Use `scripts/deploy.sh` with the new semver version:

```bash
./scripts/deploy.sh 0.3.0
```

Or run it with no argument to pick patch/minor/major interactively:

```bash
./scripts/deploy.sh
```

The script verifies the working tree is clean, the tag doesn't already exist, and that compile + tests pass. It then bumps the version in `mix.exs`, commits, tags `v0.3.0`, and pushes both `main` and the tag. GitHub Actions takes it from there to build the Docker image and deploy.

### Syncing images to server

```bash
rsync -avz images david@edenflowers-server:/opt/edenflowers_store/
```

## Maintenance mode

The site can be put into maintenance mode, which redirects all visitors to `/maternity`. It is configured via environment variables.

Set `MAINTENANCE_MODE=true` to enable. Set `MAINTENANCE_BYPASS_SECRET` to a secret value to allow previewing the site while maintenance mode is active.

To preview the site while maintenance mode is active, append `?preview=<secret>` to any URL. This sets a session cookie so subsequent requests also bypass the maintenance page.
