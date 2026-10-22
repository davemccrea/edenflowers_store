# Eden Flowers

## Development

### Email copy review

Run `just email-previews` to export the customer email scenarios to
`tmp/email-previews/{en-GB,sv,fi}.md`. The command uses fictional data and the
real email builders without starting the database, job workers or HTTP server.
It does not send email. The same scenarios are available at `/admin/emails`.

When changing conditional email copy, update `Edenflowers.Email.Previews` so
the affected wording can be reviewed. The catalogue covers curated scenarios,
not every possible combination of data.

### First-time setup

```bash
git config core.hooksPath .githooks
brew install just
just typst-install
```

`just typst-install` puts the pinned [Typst](https://typst.app) CLI in `~/.local/bin`. Receipt PDFs are rendered with it, so the confirmation-email tests fail without it. `just dev` and `just test` stop early if it's missing.

`.githooks/pre-commit` formats staged Elixir (`mix format`) and JS/CSS (Prettier via `npx`). `pre-push` runs `mix precommit`.

The remote commands (`just images-sync`, `server-logs`, `server-console`) connect through these aliases in `~/.ssh/config`. Server IPs stay out of this public repo; the origin is behind Cloudflare.

```
Host edenflowers-production
    HostName <production IP>
    User <you>
```

### Commands

Run `just` to see the commands grouped by purpose.

```bash
just dev                        # dev server at localhost:4000, with .env loaded and a local imgproxy on 4001
PORT=4001 just dev              # same, on another port (also honoured by stripe-listen)
just test [args]                # run the test suite
just stripe-listen              # forward Stripe webhooks to the dev server
just issues                     # issue board at 127.0.0.1:6420 (npm i -g backlog.md)
just db-reset                   # drop and migrate dev + test
just db-seed local              # seed the local database (run after db-reset)
just db-seed production         # one-off base seed of an empty production database
just db-backup production       # pg_dump the production database into tmp/
just rollback production v1.6.0 [tmp/<dump>] # run an old release, restoring a dump if given
just deploy production [0.3.0]  # tag a release from main (prompts for version if omitted)
just deploy-watch               # follow the latest deploy run
just images-sync                # push images/ to production and pull its uploads
just server-logs production     # tail app logs on a server
just server-console production  # remote IEx on a server
```

`just deploy production` checks the tree is clean, `main` matches origin, and `mix precommit` passes, then bumps `mix.exs`, tags `vX.Y.Z` and pushes. GitHub Actions builds the image and deploys. Plain pushes deploy nothing.

`images/` is gitignored, so photos reach production only through `just images-sync`, which `just deploy` runs before pushing. It deletes files removed locally from the server, at most 20 per run (more fails the sync, and with it the deploy), but never touches photos uploaded through the admin (`images/uploads/`, never pushed to). A rollback to a release that uses a deleted photo shows it missing. The sync also mirrors those uploads into the local `images/uploads/`, deleting at most 20 per run, so this machine keeps a copy. Filenames must be ASCII.

In dev, `just dev` starts imgproxy in Docker (OrbStack) on `PORT+1` and points `IMGPROXY_PREFIX` at it, so unsynced photos and admin uploads show up locally. It reads `images/` read-only; uploads land in `tmp/uploads`. The container keeps running after the server stops.

### Database

- `mix ash_postgres.generate_migrations NAME`: generate migrations
- `./scripts/regen-schema.sh`: drop the database, delete all migrations and resource snapshots, regenerate them from the Ash resources, and re-seed. For breaking schema changes before there's production data to migrate.

### Translations

- `mix gettext.extract`: extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext`: update all locale-specific .po files

### Papra expense capture

Upload a document to [Papra](https://papra.app) and tag it `receipt`. That fires a webhook to `/webhook/papra`, and the app sends the document to Claude to extract the expense, then tags the document `processed`. Deleting the expense in admin removes both tags. Needs `PAPRA_BASE_URL`, `PAPRA_API_KEY`, `PAPRA_WEBHOOK_SECRET`, `PAPRA_ORGANIZATION_ID` and `ANTHROPIC_API_KEY` in `.env`. The `processed` tag must already exist in Papra, and the API key needs `documents:read`, `documents:update` and `tags:read`.

### Stripe webhooks in dev

Order finalization and the confirmation email depend on `payment_intent.succeeded`. Run `just stripe-listen` (or `PORT=4001 just stripe-listen` if the server is on another port) and set the `whsec_...` it prints as `STRIPE_WEBHOOK_SECRET`.

### Worktrees

[worktrunk](https://worktrunk.dev) manages parallel worktrees. Hooks in `.config/wt.toml` copy `deps/` and `_build/`, give each worktree its own database and port in `.env`, and seed it. `just dev` then works as normal.

```bash
wt switch --create feature/my-feature
wt list
wt remove
```

## Deployment

Servers are provisioned by [phoenix-ansible](https://github.com/davemccrea/phoenix-ansible). Deploys run via `.github/workflows/deploy.yml`. See [Commands](#commands).

### Rolling back

A rollback lasts until the next deploy, which pulls the newest image again. Fix forward on `main`, then deploy as usual.

**Code only.** If the bad release's migrations only added columns or tables, the old code runs fine on the new schema and no data is lost:

```bash
just rollback production v1.6.0
```

It lists the migrations the old release will run without and asks before starting it.

**Code and database.** Needed when a migration renamed or dropped something, or corrupted data. Everything written since the dump is lost, so check Stripe for payments to reconcile afterwards.

```bash
just rollback production v1.6.0 tmp/production-v1.6.0-20261021T114210.dump
```

It asks before doing anything, backs up the current database first (so the rollback can be undone the same way), then restores the dump and starts that release. The dump must come from the same server, and from while that tag was running.

Where to find the dump:

- `just deploy production` backs up just before pushing, into `tmp/production-v<running release>-<timestamp>.dump`, and prints the rollback command.
- Otherwise use a nightly dump. The server keeps 30 days of them, taken at 02:00. Copy one into `tmp/`, naming it after the release that was live then (the last tag before 02:00, from `git for-each-ref --sort=-creatordate --format='%(creatordate:iso) %(refname:short)' refs/tags`):

  ```bash
  ssh edenflowers-production "sudo ls -lt /opt/edenflowers_store/backups/"
  ssh edenflowers-production "sudo cat /opt/edenflowers_store/backups/edenflowers_store_prod_20261021T020000.dump" \
    > tmp/production-v1.6.0-20261021T020000.dump
  ```

## Maintenance mode

`MAINTENANCE_MODE=true` redirects visitors to `/back-soon`. Signed-in admins, and the sign-in and admin paths, are let through.
