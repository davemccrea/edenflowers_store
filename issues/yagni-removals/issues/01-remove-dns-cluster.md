# Remove DNSCluster

Status: done
Type: chore

## Problem

`dns_cluster` is a Phoenix generator default for clustering nodes over DNS. The app runs as a single container per host under `docker compose`, and `DNS_CLUSTER_QUERY` is set nowhere (`scripts/`, `rel/`, compose), so the child always starts with `:ignore`.

## What to build

- `mix.exs`: remove `{:dns_cluster, "~> 0.3.0"}`; `mix deps.unlock dns_cluster` so `mix.lock` drops it.
- `lib/edenflowers/application.ex`: remove the `{DNSCluster, ...}` child.
- `config/runtime.exs`: remove `config :edenflowers, :dns_cluster_query, ...`.

## Acceptance criteria

- [x] `grep -ri dns_cluster` finds nothing outside `deps/`
- [x] `mix compile --warnings-as-errors` and the existing suite pass
- [ ] Staging boots after deploy

## Comments

Removed the dep, the supervisor child and the runtime config; compile with warnings-as-errors and the suite (1283 tests) pass. Left: deploy to staging and confirm it boots.
