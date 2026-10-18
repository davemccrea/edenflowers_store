---
id: TASK-21
title: Enforce one module layout and dependency style with Credo
status: ready-for-agent
assignee: []
created_date: '2026-10-18 04:05'
updated_date: '2026-10-18 11:24'
labels:
  - spec
dependencies: []
priority: low
type: chore
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
One way to declare dependencies and lay out modules, checked by Credo so it stays that way

**Why:** Nothing enforces module conventions, so the code has drifted into several styles and new code adds more.

### Problem

Nothing enforces module conventions: `.formatter.exs` only formats, and there's no Credo, Styler or similar. `mix precommit`'s `compile --warnings-as-errors` already catches unused aliases and imports. An audit of `lib/` (236 files, October 2026) found:

**Already consistent, keep:**
- The Ash DSL section order in every resource: postgres, translations/resource/archive, state_machine, oban, paper_trail, actions, policies, pub_sub, preparations, changes/validations, attributes, relationships, calculations, aggregates, identities. Code interfaces live in the domains.
- Enums used by one resource defined above it in the same file; shared ones in their own file.
- Relationship targets written out in full.
- Directive order `use`, `require`, `import`, `alias` in ~225 files.
- One alias per line (321 lines vs 16 grouped).
- Domain subdirectories `changes/`, `validations/`, `calculations/`, `actions/`, `workers/`, `checks/`, `preparations/`.

**Inconsistent:**
- Ash `change`/`validate` lines: module names aliased in some resources, written out in full in others, sometimes both in one file. ~63 full names vs ~78 aliased across resources.
- `@impl true`: on every callback in the admin LiveViews; on none in the customer-facing LiveViews, LiveComponents or Oban workers.
- `render` before the event handlers in 9 LiveViews, after them in 13.
- `require Ash.Query` and a whole-module `import Ash.Expr` inside the search helper of six admin list pages.
- 24 of 76 files with several aliases leave them unsorted; 8 files mix grouped and single aliases; 8 files deviate from the directive order.
- Smaller: `Edenflowers.Actors.system_actor()` written in full 15 times while 15 files import `Edenflowers.Actors`; enums referenced as `__MODULE__.X`, by full name or by alias; module attributes declared mid-module.

### Decisions

1. **Credo, not Styler.** Styler would enforce aliases automatically, but orders `require` last (rewriting ~42 files against the dominant order) and its first run rewrites far more than conventions (pipes, `case` to `if`, number formats). Credo checks what we already do, with a small diff, and runs in `mix precommit`.
2. **The conventions:**
   - Directives at the top of the module, after `@moduledoc`, in the order `use`, `require`, `import`, `alias`. None inside functions.
   - One alias per line, sorted alphabetically, no `{}` grouping. `as:` only where a name would clash (`AdminComponents` today).
   - Imports name what they bring in with `only:`, except `Plug.Conn`, `Phoenix.Component` and the project's component modules (`EdenflowersWeb.Admin.Components`, `CoreComponents`).
   - Module attributes directly after the directives.
   - Ash resources: alias the domain's `Changes`, `Validations`, `Calculations` and `Actions`, and other domains' too (`Edenflowers.Payments.Changes`), and use the short names in `change`/`validate`/`calculate` lines. Relationship targets stay in full.
   - A resource's own inline enums are referenced as `__MODULE__.Name`.
   - `@impl true` on every behaviour callback: LiveViews, LiveComponents, Oban workers, plugs, Ash changes and validations.
   - LiveView order: `mount`, `handle_params`, `render`, then `handle_event`, `handle_info`, `handle_async`, then function components and private helpers.
   - Where a module imports `Edenflowers.Actors`, call `system_actor()` short.
3. **Directory oddities are left alone** unless a ticket touches them: `error_alerts/` and `expressions/` (one file each), the four helper modules in `features/admin/` (`order_log.ex`, `subscription_log.ex`, `push_subscriptions.ex`, `calendar_view_model.ex`), and `wedding_enquiry/send_emails.ex`. Moving them is churn for little gain.

### Out of scope

- Credo's other checks (refactoring, design, warnings) beyond those named in `TASK-21.1`. Turn more on later, one at a time, if wanted.
- test/ beyond what Credo flags; it follows the same conventions with a handful of deviations.
<!-- SECTION:DESCRIPTION:END -->
