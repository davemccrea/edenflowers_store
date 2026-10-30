---
id: TASK-149
title: Add swap to the production server
status: needs-triage
assignee: []
created_date: '2026-10-30 17:43'
labels:
  - spec
  - developers
  - admin
dependencies: []
priority: medium
type: chore
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Give the production server a swap file, provisioned by the Ansible role in `infra/`, so a memory spike slows the server down instead of killing a container.

**Why:** The server has 3.7 GiB RAM and no swap (checked 2026-10-30: 2.3 GiB available, app ~510 MB, Papra ~140 MB, imgproxy ~50 MB, cloudflared ~17 MB, Umami about to join). Without swap, the kernel OOM killer picks a process when memory runs out, which could be the app mid-checkout or Postgres.

Rough shape:
- A task in `roles/common/tasks/` that creates a swap file, enables it and adds it to `/etc/fstab`, idempotently
- A low `vm.swappiness` so swap only absorbs spikes

Open questions:
- Swap size (1x RAM? 2 GiB?)
- Swappiness value
- Is the disk big enough, and does Hetzner storage make swap writes a concern?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provisioning creates and enables a swap file that survives reboot
- [ ] #2 Re-running provision changes nothing
<!-- AC:END -->
