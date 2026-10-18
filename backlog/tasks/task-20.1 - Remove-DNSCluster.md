---
id: TASK-20.1
title: Remove DNSCluster
status: done
assignee: []
created_date: '2026-10-18 03:31'
labels: []
dependencies: []
parent_task_id: TASK-20
type: chore
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

`dns_cluster` is a Phoenix generator default for clustering nodes over DNS. The app runs as a single container per host under `docker compose`, and `DNS_CLUSTER_QUERY` is set nowhere (`scripts/`, `rel/`, compose), so the child always starts with `:ignore`.

### What to build

- `mix.exs`: remove `{:dns_cluster, "~> 0.3.0"}`; `mix deps.unlock dns_cluster` so `mix.lock` drops it.
- `lib/edenflowers/application.ex`: remove the `{DNSCluster, ...}` child.
- `config/runtime.exs`: remove `config :edenflowers, :dns_cluster_query, ...`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `grep -ri dns_cluster` finds nothing outside `deps/`
- [x] #2 `mix compile --warnings-as-errors` and the existing suite pass
- [ ] #3 Staging boots after deploy
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-18 07:18

---

Removed the dep, the supervisor child and the runtime config; compile with warnings-as-errors and the suite (1283 tests) pass. Left: deploy to staging and confirm it boots.

---
<!-- COMMENTS:END -->
