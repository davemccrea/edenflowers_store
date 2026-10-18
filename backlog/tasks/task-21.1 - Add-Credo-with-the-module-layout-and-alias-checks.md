---
id: TASK-21.1
title: Add Credo with the module-layout and alias checks
status: done
assignee: []
created_date: '2026-10-18 04:05'
labels: []
dependencies: []
parent_task_id: TASK-21
type: chore
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

- `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` in `mix.exs`.
- `.credo.exs` that enables only these checks, so the first run reports conventions and nothing else:
  - `Credo.Check.Readability.StrictModuleLayout`, configured `order: [:moduledoc, :behaviour, :use, :require, :import, :alias, :module_attribute]`, ignoring `:module_attribute` if it flags attributes that legitimately follow a `use` (e.g. `use Oban.Worker` options), and with `ignore` for whatever proves noisy.
  - `Credo.Check.Readability.AliasOrder`
  - `Credo.Check.Readability.MultiAlias`
  - `Credo.Check.Consistency.MultiAliasImportRequireUse`
  - `Credo.Check.Design.AliasUsage`, with `if_nested_deeper_than: 1` and `if_called_more_often_than: 1`, and `excluded_namespaces` / `excluded_lastnames` for anything that reads worse aliased. Check what it flags in Ash DSL blocks; if it doesn't see module arguments there, ticket 02's sweep covers them.
- `"credo --strict"` in the `precommit` alias in `mix.exs`, after `format --check-formatted`.
- Fix everything the checks flag. Mostly mechanical: sorting aliases, splitting grouped ones, reordering the 8 files with directives out of order, moving the six `require Ash.Query` / `import Ash.Expr` out of the admin search helpers (with `only: [expr: 1]`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `mix credo --strict` passes on lib/ and test/
- [x] #2 `mix precommit` runs Credo and passes
- [x] #3 No behaviour change; the existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-18 07:25

---

Landed with three departures from the plan:

- `Design.AliasUsage` uses `if_nested_deeper_than: 2`, not 1. At 1 it flags two-part names such as `Ash.Changeset`, `Plug.Test` and `AshPhoenix.Form` (812 hits), which the code always writes in full.
- `StrictModuleLayout` order has `:shortdoc` between `:alias` and `:module_attribute`, so Mix tasks keep `@shortdoc` after `use Mix.Task`.
- `CoreComponents.flower/1`'s `attr ... values: Map.keys(@flowers)` reads as a mid-module attribute to Credo; it has a one-line disable.

AliasUsage only sees calls (`Mod.fun()`), not module arguments in Ash DSL (`change Edenflowers.Orders.Changes.X`), so ticket 02 covers those.

---
<!-- COMMENTS:END -->
