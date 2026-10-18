---
id: TASK-6
title: Simplify dev seeds
status: ready-for-human
assignee: []
created_date: '2026-10-10 22:45'
updated_date: '2026-10-18 05:08'
labels: []
dependencies: []
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cut the dev seeds down to the fixtures that put a screen into a state someone actually checks

`priv/repo/seeds.exs` is ~1,250 lines on top of `priv/repo/seeds/production.exs`. Which fixtures go is the owner's call: see `TASK-6.1`.
<!-- SECTION:DESCRIPTION:END -->
