---
id: TASK-110
title: Developer role that hides the System tools from the shop admin
status: done
assignee: []
created_date: '2026-10-23 20:28'
updated_date: '2026-10-27 13:57'
labels:
  - spec
  - admin
  - wontfix
dependencies: []
priority: medium
type: feature
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the admin boolean on User with a role, so the developer keeps the System tools and the shop admin no longer sees or reaches them.

**Why:** Jennie's admin sidebar is crowded with tools only the developer uses, and AshAdmin can edit any record past the normal order rules, so stumbling into it risks bad data. A role also leaves room for later staff roles such as driver.

## Decisions

- **Role:** `Edenflowers.Accounts.Role`, an `Ash.Type.Enum` of `:customer | :admin | :developer`. `User.role` defaults to `:customer` and stays `writable?: false`, set only by seeds or a data fix. No in-app way to change it.
- **Hierarchy:** a developer can do everything an admin can, plus the System tools. `Role.admin_roles/0` returns `[:admin, :developer]` and is the only place that list lives. `Role.admin?/1` and `Role.developer?/1` build on it.
- **Who:** mail@dmccrea.me is `:developer`, info@edenflowers.fi is `:admin`.
- **Policies:** one simple check, `Edenflowers.Accounts.Checks.Admin` (`Ash.Policy.SimpleCheck`, true when `Role.admin?(actor.role)`). The admin and system-actor bypasses move from the 16 resources to their domains' `policies` (domain gets `extensions: [Ash.Policy.Authorizer]`), as the Ash docs recommend. The AshAuthentication bypass stays on User. No developer check in Ash: nothing in Ash is developer-only.
- **Filters:** `PushSubscription.admin_devices` becomes `expr(user.role in ^Role.admin_roles())`.
- **Developer-only tools:** Email previews, Errors, Oban, AshAdmin. Admins don't see the System section of the sidebar. A new `:live_developer_required` on_mount guards `/admin/emails`, `/admin/errors` and `/admin/ash`, and redirects a signed-in admin to `/admin` with no flash. `ObanResolver` checks `Role.developer?`.
- **Other admin checks** (maintenance plug, report and avatar controllers, dev OTP prefill, `SubscriptionChangesOpen`) switch to `Role.admin?` and behave as today. `SubscriptionChangesOpen` stays a validation on purpose: a policy would turn the customer's "It's too late to change your next delivery" field error into a generic forbidden.
- **Seeds:** `priv/repo/seeds/production.exs` sets roles with `Ash.Seed` and drops its raw-SQL UPDATE.
- **Migration and rollout:** one release, generated migration only (drops `admin`, adds `role`). Right after `just deploy`, run a data fix over rpc with `Ash.Seed.update!` to set both roles. Nobody can reach the admin in between, so deploy at a quiet time.
- **Future roles:** `admin_roles/0` lists roles explicitly, so a new role such as `:driver` gets nothing until granted. Its permissions go in resource policies (`actor_attribute_equals(:role, :driver)`) and its pages in their own live session. Revisit AshRbac once several roles need different permissions on the same resources.

## To verify while implementing

- A domain-level bypass applies ahead of each resource's own policies, including resources that set `authorizers: [Ash.Policy.Authorizer]` themselves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 User has a role attribute (customer, admin, developer) and no admin attribute, via a generated migration
- [ ] #2 The admin and system bypasses live on the domains, and no resource repeats them
- [ ] #3 Policy tests cover a customer, an admin and a developer actor
- [ ] #4 An admin sees no System section in the admin sidebar
- [ ] #5 An admin opening /admin/emails, /admin/errors, /admin/oban or /admin/ash is turned away (redirected to /admin where the route allows)
- [ ] #6 A developer keeps every admin page and every System tool
- [ ] #7 Push notifications, maintenance mode, reports, avatars and subscription changes treat developers and admins alike, as today
- [ ] #8 production.exs seeds roles with Ash.Seed and no raw SQL
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: closed. Jennie can ignore the System section. Revisit when a second staff role (e.g. driver) is real.

---
<!-- COMMENTS:END -->
