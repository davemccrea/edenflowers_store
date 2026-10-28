---
id: TASK-140
title: Improve the account page
status: needs-triage
assignee: []
created_date: '2026-10-28 19:23'
labels:
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 273000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rework /account so a signed-in customer sees what matters at a glance.

**Why:** The account page is where customers manage subscriptions and see upcoming orders. Today an empty account is a stack of near-identical empty sections, which looks unfinished and buries the one action that matters.

Raised in review note #11 (sv, desktop). Observations from the empty state:

- Two empty sections in a row (Kommande, Prenumerationer), each with its own links; together they read as a list of nothing.
- Kommande offers two calls to action (Gå till butiken, Se kommande kurser) and Prenumerationer a third, all styled the same.
- The newsletter section repeats itself: the description and the help text both say "Bara enstaka utskick".
- Sign out sits next to the greeting as an outline button, as prominent as anything else on the page.

Open questions: should empty sections collapse into one welcome block? Which single call to action leads? Does sign out belong lower or in the header menu? What does the page look like with a subscription and upcoming orders (not reviewed yet)?
<!-- SECTION:DESCRIPTION:END -->
