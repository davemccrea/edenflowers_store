# Eden Flowers

## Development

### First-time setup

```bash
git config core.hooksPath .githooks
brew install just
just install-typst
```

`just install-typst` puts the pinned [Typst](https://typst.app) CLI in `~/.local/bin`. Receipt PDFs are rendered with it, so `just dev` and `just test` stop early if it's missing.

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
PORT=4001 just dev              # same, on another port (also honoured by forward-stripe)
just test [args]                # run the test suite
just format                     # format Elixir, JS and CSS
just forward-stripe             # forward Stripe webhooks to the dev server
just open-issues                # issue board at 127.0.0.1:6420 (npm i -g backlog.md)
just reset-db                   # drop and migrate dev + test
just seed-db [--stripe]         # seed the local database (run after reset-db)
just deploy [0.3.0]             # tag a release from main (prompts for version if omitted)
just rollback v1.6.0 [tmp/<dump>] # run an old release, restoring a dump if given
just backup                     # pg_dump the production database into tmp/
just push-images                # push images/ to production
just pull-images                # download production's images/ (new machine)
just tail-logs                  # tail app logs
just open-console               # remote IEx
just provision                  # apply infra/ to the server (check-provision for a dry run)
```

In dev, `just dev` starts imgproxy in Docker (OrbStack) on `PORT+1`, reading `images/` read-only and dev uploads from `tmp/uploads`. The container keeps running after the server stops.

### Stripe webhooks

Order finalization and the confirmation email depend on `payment_intent.succeeded`. Run `just forward-stripe` and set the `whsec_...` it prints as `STRIPE_WEBHOOK_SECRET`.

### Email copy

`/admin/emails` shows every customer email scenario with fictional data, in English, Swedish and Finnish. When changing conditional email copy, add the case to `Edenflowers.Email.Previews`.

### Database and translations

- `mix ash_postgres.generate_migrations NAME`: generate migrations from the Ash resources
- `mix gettext.extract` then `mix gettext.merge priv/gettext`: update the .pot and .po files

Adding a language means adding it in three places, whose defaults differ on purpose (`sv-FI` is the shop's locale, `en` is the source text's): `Edenflowers.Locales`, `config :localize`'s `supported_locales`, and `EdenflowersWeb.Gettext`'s `locales`. Then add `priv/gettext/<language>/LC_MESSAGES/{default,routes}.po`. `Edenflowers.PinsTest` fails if the lists disagree.

### Papra expense capture

Every document uploaded to [Papra](https://papra.app) is a receipt or invoice. Papra's `document:created` webhook hits `/webhook/papra`, the app sends the document to Claude to extract the expense, then renames it after the receipt date and vendor (`2026-10-23 Kukkatukku Oy.pdf`), so a document still under its original name hasn't been processed. Correcting the date or vendor in admin renames it again. Deleting an expense in admin leaves the document in Papra; to import it again, delete the document in Papra and upload the PDF again. The API key needs `documents:create`, `documents:read` and `documents:update`.

Invoice emails import themselves. A Fastmail filter (Settings → Filters & Rules) moves invoice emails, such as Hetzner's, into the folder `Fakturor`, and any invoice email can be dragged there by hand. Every 15 minutes production uploads each PDF attachment to Papra, which sends it for extraction like any other upload, and moves the email to `Fakturor/Importerade`. Emails without a PDF stay in `Fakturor` to handle by hand. Both folders must exist. Production reads the mailbox with `FASTMAIL_API_TOKEN` (Settings → Privacy & Security → API tokens, with mail write access, since emails are moved). Dev and worktrees have no token, so they never touch the mailbox.

### Worktrees

[worktrunk](https://worktrunk.dev) manages parallel worktrees. `.config/wt.toml` copies gitignored files such as `deps/`, `.env` and `infra/.vault_pass` from the main checkout, gives the worktree its own database and port, and seeds it. `wt remove` drops its databases and stops its imgproxy.

```bash
wt switch --create feature/my-feature
wt remove
```

## Deployment

`just deploy` checks the tree is clean and `main` isn't behind origin, runs `mix precommit`, pushes images, bumps `mix.exs` and tags `vX.Y.Z`. After you confirm, it backs up the production database, pushes, watches the GitHub Actions deploy and publishes release notes. Plain pushes deploy nothing.

`images/` is gitignored, so photos reach production only through `just push-images`. It deletes server files removed locally, but only when you allow it: any deletion fails the push and the deploy and lists the files, and `MAX_DELETE=<n>` lets that many through. If this machine never had those files, `just pull-images` downloads them without deleting anything locally. Neither touches admin uploads in `images/uploads/`, which the Storage Box backs up (see `infra/README.md`). Filenames must be ASCII.

The server itself is provisioned by Ansible in `infra/`, see [infra/README.md](infra/README.md).

### Rolling back

A rollback lasts until the next deploy. Fix forward on `main`, then deploy as usual.

**Code only.** If the bad release's migrations only added columns or tables, the old code runs fine on the new schema:

```bash
just rollback v1.6.0
```

It lists the migrations the old release will run without and asks before starting it.

**Code and database.** Needed when a migration renamed or dropped something, or corrupted data. Everything written since the dump is lost, so check Stripe for payments to reconcile afterwards.

```bash
just rollback v1.6.0 tmp/production-v1.6.0-20261021T114210.dump
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

`maintenance_mode` in `infra/group_vars/all/vars.yml` sets `MAINTENANCE_MODE`, which redirects visitors to `/back-soon`. Signed-in admins, and the sign-in, admin and payment-link paths, are let through.
