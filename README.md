# Edenflowers

## Deploying to Production

1. Update the version in `mix.exs` (e.g. `0.1.0` → `0.2.0`)
2. Commit the change: `git commit -am "Bump version to v0.2.0"`
3. Tag the commit: `git tag v0.2.0`
4. Push the tag: `git push origin v0.2.0`

GitHub Actions will build the Docker image and deploy it to the server automatically.

## Hints

- `mix ash_postgres.generate_migrations NAME` to generate migrations
- `mix ash.setup` to install and setup dependencies
- `mix run priv/repo/seeds.exs` to seed the database
- `iex -S mix phx.server` to start the Phoenix endpoint
- `mix gettext.extract` to extract gettext() calls to .pot files
- `mix gettext.merge priv/gettext` to update all locale-specific .po files

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
