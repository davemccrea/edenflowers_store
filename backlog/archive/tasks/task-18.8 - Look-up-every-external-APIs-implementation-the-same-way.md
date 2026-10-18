---
id: TASK-18.8
title: Look up every external API's implementation the same way
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:12'
updated_date: '2026-10-18 11:35'
labels:
  - quick
dependencies: []
parent_task_id: TASK-18
type: refactor
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Each external API's mock is looked up a different way, so a reader has to know the convention to follow a call.

### Problem

`config/test.exs` swaps each external API for a Mox mock (`:stripe_api`, `:here_api`, `:papra_api`, `:claude_api`). Stripe looks its implementation up once, in `StripeAPI.impl/0`. The others are looked up at each call site:

- `HereAPI`: `CalculateDelivery.here_api/0`
- `PapraAPI`: `Expenses.Changes.Process.papra/0` and `Expenses.Changes.RemovePapraTags.papra/0`
- `ClaudeAPI`: `Expenses.Changes.Process.claude/0` and `Admin.TranslationFields.claude/0`

Each repeats the config key and the default module, so a reader has to know the convention to see why a call goes through a private function.

### What to build

- `impl/0` on `HereAPI`, `PapraAPI` and `ClaudeAPI`, matching `StripeAPI.impl/0`.
- Call sites use `HereAPI.impl().geocode(...)` and so on; the private lookup functions go.

### Tests

- The existing suite passes unchanged; the config keys stay the same.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `Application.get_env(:edenflowers, :…_api, …)` appears only inside the `External` modules
- [ ] #2 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 11:35

---

Moved to TASK-28 as a spec of its own: it doesn't depend on the rest of TASK-18.

---
<!-- COMMENTS:END -->
