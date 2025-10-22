#!/bin/bash

mix ecto.drop

find priv/repo/migrations -type f ! -name ".formatter.exs" -delete
rm -rf priv/resource_snapshots

mix ash_postgres.generate_migrations initial
mix oban.install

mix ash.setup
mix run priv/repo/seeds.exs
