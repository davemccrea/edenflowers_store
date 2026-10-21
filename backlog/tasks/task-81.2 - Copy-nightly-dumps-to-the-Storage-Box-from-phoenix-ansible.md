---
id: TASK-81.2
title: Copy nightly dumps to the Storage Box from phoenix-ansible
status: ready-for-agent
assignee: []
created_date: '2026-10-21 08:32'
updated_date: '2026-10-21 08:49'
labels: []
dependencies:
  - TASK-81.1
parent_task_id: TASK-81
type: task
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This is the actual off-site copy.

In phoenix-ansible roles/common/tasks/backups.yml:
- Generate an SSH key for the postgres user (it owns the backup folder) and print the public key. The human installs it with `cat key.pub | ssh -p23 <sub>@<sub>.your-storagebox.de install-ssh-key`.
- Pin the box's host key in known_hosts.
- Chain onto the existing dump-and-prune cron job: `rsync -a --delete -e 'ssh -p23' /opt/edenflowers_store/backups/ <sub>@<host>:edenflowers/`.
- On success, ping a healthchecks.io check (URL in the vault). healthchecks.io emails when a ping is missed, which covers both failures and a cron that never ran.
- Sub-account username, hostname and ping URL go in vault.yml and vault.example.yml. Production only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The nightly job mirrors the backup folder to the Storage Box over SSH on port 23
- [ ] #2 A successful run pings healthchecks.io, and a missed ping sends an email
<!-- AC:END -->
