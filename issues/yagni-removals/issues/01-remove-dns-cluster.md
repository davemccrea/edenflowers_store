# Remove DNSCluster

Status: ready-for-agent
Type: chore

## Problem

`dns_cluster` is a Phoenix generator default for clustering nodes over DNS. The app runs as a single container per host under `docker compose`, and `DNS_CLUSTER_QUERY` is set nowhere (`scripts/`, `rel/`, compose), so the child always starts with `:ignore`.

## What to build

- `mix.exs`: remove `{:dns_cluster, "~> 0.3.0"}`; `mix deps.unlock dns_cluster` so `mix.lock` drops it.
- `lib/edenflowers/application.ex`: remove the `{DNSCluster, ...}` child.
- `config/runtime.exs`: remove `config :edenflowers, :dns_cluster_query, ...`.

## Acceptance criteria

- [ ] `grep -ri dns_cluster` finds nothing outside `deps/`
- [ ] `mix compile --warnings-as-errors` and the existing suite pass
- [ ] Staging boots after deploy

## Comments
