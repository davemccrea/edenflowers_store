# Eden Flowers

## Deploying to Production

1. Update the version in `mix.exs` (e.g. `0.1.0` → `0.2.0`)
2. Commit the change: `git commit -am "Bump version to v0.2.0"`
3. Tag the commit: `git tag v0.2.0`
4. Push the tag: `git push origin v0.2.0`

GitHub Actions will build the Docker image and deploy it to the server automatically.

## Regenerating migrations

During development, when making breaking schema changes it's often easier to regenerate all migrations from scratch rather than layering new ones. `regen.sh` automates this:

```bash
./regen.sh
```

It drops the database, deletes all existing migrations and resource snapshots, regenerates them fresh from the current Ash resource definitions, and re-seeds the database.

## Common commands

- `mix ash_postgres.generate_migrations NAME` to generate migrations
- `mix ash.setup` to create the database, run migrations, and seed
- `mix run priv/repo/seeds.exs` to seed the database
- `iex -S mix phx.server` to start the server at [`localhost:4000`](http://localhost:4000)
- `mix gettext.extract` to extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext` to update all locale-specific .po files
