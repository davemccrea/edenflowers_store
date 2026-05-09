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

### Database

- `mix ash.setup` — create the database, run migrations, and seed
- `mix run priv/repo/seeds.exs` — seed the database
- `mix ash_postgres.generate_migrations NAME` — generate migrations

#### Regenerating migrations

When making breaking schema changes it's often easier to regenerate all migrations from scratch. `regen.sh` automates this:

```bash
./regen.sh
```

It drops the database, deletes all existing migrations and resource snapshots, regenerates them fresh from the current Ash resource definitions, and re-seeds the database.

### Translations

- `mix gettext.extract` — extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext` — update all locale-specific .po files

### Git workflow

```bash
# Create a feature branch
git checkout -b feature/my-feature

# Push and create a PR
git push -u origin feature/my-feature
gh pr create --title "My feature title" --body ""

# To open a PR with no real commits yet, use an empty commit
git commit --allow-empty -m "Start my feature"
git push

# After PR is merged, clean up
git checkout main
git pull
git branch -d feature/my-feature
```

## Deployment

### Releasing a new version

Use `deploy.sh` with the new semver version:

```bash
./deploy.sh 0.3.0
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
