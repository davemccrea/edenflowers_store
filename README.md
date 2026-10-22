# Eden Flowers

## Development

### First-time setup

```bash
git config core.hooksPath .githooks
brew install just
just typst-install
```

`just typst-install` puts the pinned [Typst](https://typst.app) CLI in `~/.local/bin`. Receipt PDFs are rendered with it, so `just dev` and `just test` stop early if it's missing.

`.githooks/pre-commit` checks the formatting of staged Elixir and JS/CSS files (`just format` fixes it). `pre-push` runs `mix precommit`.

Remote commands connect through this alias in `~/.ssh/config`. Server IPs stay out of this public repo; the origin is behind Cloudflare.

```
Host edenflowers-production
    HostName <production IP>
    User <you>
```

### Commands

Run `just` to see every command, grouped by purpose.

```bash
just dev                        # dev server at localhost:4000, with .env loaded and a local imgproxy on 4001
PORT=4001 just dev              # same, on another port (also honoured by stripe-listen)
just test [args]                # run the test suite
just format                     # format Elixir, JS and CSS
just stripe-listen              # forward Stripe webhooks to the dev server
just email-previews             # export customer email wording to tmp/email-previews/
just issues                     # issue board at 127.0.0.1:6420 (npm i -g backlog.md)
just db-reset                   # drop and migrate dev + test
just db-seed local              # seed the local database (run after db-reset)
just db-backup production       # pg_dump the production database into tmp/
just deploy production [0.3.0]  # tag a release from main (prompts for version if omitted)
just rollback production v1.6.0 [tmp/<dump>] # run an old release, restoring a dump if given
just images-sync                # push images/ to production and pull its uploads
just server-logs production     # tail app logs
just server-console production  # remote IEx
just provision production       # apply infra/ to the server (provision-check for a dry run)
```

In dev, `just dev` starts imgproxy in Docker (OrbStack) on `PORT+1`, reading `images/` read-only and dev uploads from `tmp/uploads`. The container keeps running after the server stops.

### Stripe webhooks

Order finalization and the confirmation email depend on `payment_intent.succeeded`. Run `just stripe-listen` and set the `whsec_...` it prints as `STRIPE_WEBHOOK_SECRET`.

### Email copy

`just email-previews` renders the customer email scenarios with fictional data, in English, Swedish and Finnish, without sending anything. The same scenarios are at `/admin/emails`. When changing conditional email copy, add the case to `Edenflowers.Email.Previews`.

### Database and translations

- `mix ash_postgres.generate_migrations NAME`: generate migrations from the Ash resources
- `mix gettext.extract` then `mix gettext.merge priv/gettext`: update the .pot and .po files

### Papra expense capture

Tag a document `receipt` in [Papra](https://papra.app). Its webhook hits `/webhook/papra`, the app sends the document to Claude to extract the expense, then tags it `processed`. Deleting the expense in admin removes both tags. The `processed` tag must already exist, and the API key needs `documents:read`, `documents:update` and `tags:read`.

### Worktrees

[worktrunk](https://worktrunk.dev) manages parallel worktrees. `.config/wt.toml` copies gitignored files such as `deps/`, `.env` and `infra/.vault_pass` from the main checkout, gives the worktree its own database and port, and seeds it. `wt remove` drops its databases and stops its imgproxy.

```bash
wt switch --create feature/my-feature
wt remove
```

## Deployment

`just deploy production` checks the tree is clean and `main` isn't behind origin, runs `mix precommit`, syncs images, bumps `mix.exs` and tags `vX.Y.Z`. After you confirm, it backs up the production database, pushes, watches the GitHub Actions deploy and publishes release notes. Plain pushes deploy nothing.

`images/` is gitignored, so photos reach production only through `just images-sync`. It deletes server files removed locally, at most 20 per run (more fails the sync and the deploy), and never touches admin uploads in `images/uploads/`, which it pulls back here instead. Filenames must be ASCII.

The server itself is provisioned by Ansible in `infra/`, see [infra/README.md](infra/README.md).

### Rolling back

A rollback lasts until the next deploy. Fix forward on `main`, then deploy as usual.

**Code only.** If the bad release's migrations only added columns or tables, the old code runs fine on the new schema:

```bash
just rollback production v1.6.0
```

It lists the migrations the old release will run without and asks before starting it.

**Code and database.** Needed when a migration renamed or dropped something, or corrupted data. Everything written since the dump is lost, so check Stripe for payments to reconcile afterwards.

```bash
just rollback production v1.6.0 tmp/production-v1.6.0-20261021T114210.dump
```

It backs up the current database first, so the rollback can be undone the same way. The dump must come from while that tag was running:

- `just deploy` saves one just before pushing, as `tmp/production-v<running release>-<timestamp>.dump`.
- Otherwise use a nightly dump (02:00, kept 30 days). Name it after the release that was live then (`git for-each-ref --sort=-creatordate --format='%(creatordate:iso) %(refname:short)' refs/tags`):

  ```bash
  ssh edenflowers-production "sudo ls -lt /opt/edenflowers_store/backups/"
  ssh edenflowers-production "sudo cat /opt/edenflowers_store/backups/edenflowers_store_prod_20261021T020000.dump" \
    > tmp/production-v1.6.0-20261021T020000.dump
  ```

## Maintenance mode

`maintenance_mode` in `infra/host_vars/production/vars.yml` sets `MAINTENANCE_MODE`, which redirects visitors to `/back-soon`. Signed-in admins, and the sign-in, admin and payment-link paths, are let through.
