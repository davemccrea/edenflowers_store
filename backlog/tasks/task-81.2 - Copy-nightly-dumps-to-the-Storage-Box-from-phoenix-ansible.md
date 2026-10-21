---
id: TASK-81.2
title: Copy nightly dumps to the Storage Box from phoenix-ansible
status: ready-for-agent
assignee: []
created_date: '2026-10-21 08:32'
labels: []
dependencies:
  - TASK-81.1
parent_task_id: TASK-81
type: task
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This is the actual off-site copy, plus the pruning that stops the server's backup folder filling the disk.

In phoenix-ansible roles/common/tasks/backups.yml:
- Delete dumps older than 7 days from /opt/edenflowers_store/backups/ after the 02:00 pg_dump.
- Generate an SSH key for the postgres user (it owns the backup folder) and print the public key. The human installs it with `cat key.pub | ssh -p23 <sub>@<sub>.your-storagebox.de install-ssh-key`.
- Pin the box's host key in known_hosts.
- After the dump and prune, run `rsync -a --delete -e 'ssh -p23' /opt/edenflowers_store/backups/ <sub>@<host>:edenflowers/`.
- On success, ping a healthchecks.io check (URL in the vault). healthchecks.io emails when a ping is missed, which covers both failures and a cron that never ran.
- Sub-account username, hostname and ping URL go in vault.yml and vault.example.yml. Production only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dumps older than 7 days are deleted from the server
- [ ] #2 The nightly job mirrors the backup folder to the Storage Box over SSH on port 23
- [ ] #3 A successful run pings healthchecks.io, and a missed ping sends an email
<!-- AC:END -->
