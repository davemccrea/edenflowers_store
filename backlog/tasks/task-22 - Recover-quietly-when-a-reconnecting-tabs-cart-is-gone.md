---
id: TASK-22
title: Recover quietly when a reconnecting tab's cart is gone
status: ready-for-agent
assignee: []
created_date: '2026-10-18 07:17'
updated_date: '2026-10-18 05:48'
labels: []
dependencies: []
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A storefront tab whose cart has gone recovers quietly with a fresh cart instead of crashing into a reload

ErrorTracker logged this on 2026-10-18 at 03:40 UTC, 40 minutes after the nightly `purge_abandoned_cart` run. See `TASK-22.1`.
<!-- SECTION:DESCRIPTION:END -->
