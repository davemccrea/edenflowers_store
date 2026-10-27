---
id: TASK-81.2
title: Copy nightly database dumps and uploaded photos to the Storage Box
status: done
assignee: []
created_date: '2026-10-21 08:32'
updated_date: '2026-10-27 14:07'
labels:
  - launch
dependencies:
  - TASK-81.1
parent_task_id: TASK-81
type: task
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This is the actual off-site copy.

In `infra/roles/common/tasks/backups.yml`:
- Generate an SSH key for the postgres user (it owns the backup folder) and print the public key. The human installs it with `cat key.pub | ssh -p23 <account>@<host> install-ssh-key`.
- Pin the box's host key in known_hosts.
- Chain onto the existing dump-and-prune cron job: `rsync -a --delete -e 'ssh -p23' /opt/edenflowers_store/backups/ <account>@<host>:edenflowers/database/`.
- On success, ping a Better Stack heartbeat (URL in the vault). Better Stack alerts when a ping is missed, which covers both failures and a cron that never ran.
- Main Storage Box account username, hostname and ping URL go in vault.yml and vault.example.yml. Production only.

Use the main Storage Box account for now; a dedicated sub-account is deferred. Keep the dedicated postgres transfer key and pinned host verification. Restrict the rsync destinations to `edenflowers/database/` and `edenflowers/photos/` and keep unrelated files out of it: `--delete` applies there. The key is not restricted to that directory and exposes the main account if the production server is compromised. Independently managed snapshots remain required.

Also mirror original uploaded photos from the production uploads directory (resolve the actual UPLOADS_DIR and postgres read permissions before implementation) to `edenflowers/photos/`. Keep database dumps under `edenflowers/database/`. Each rsync --delete must target only its own directory, never `edenflowers/`. Safely relocate any existing remote dumps when changing layout; do not delete the only off-site copy. Database dump, local pruning, database transfer and photo transfer must all succeed before the Better Stack heartbeat. A failed photo transfer must suppress the heartbeat too. Snapshot retention supplies photo deletion/version history; no separate photo pruning job is needed. A live photo mirror is not guaranteed to be transactionally consistent with the database dump; do not claim atomic recovery.

Keep the latest 10 daily Storage Box snapshots (the included allowance), scheduled after the 02:00 backup normally finishes; 04:00 is suggested if sufficient. This provides roughly 10 days of photo/mirror recovery, not 30 days. Dated database dumps remain retained for roughly 30 days. Snapshot configuration and restore verification are manual; successful rsync alone does not verify them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The nightly job mirrors the backup folder to the Storage Box over SSH on port 23
- [x] #2 A successful run pings a Better Stack heartbeat, and a missed heartbeat sends an alert
- [x] #3 Nightly backups mirror original uploaded photos to a separate photos/ destination without deleting database backups
- [x] #4 The success heartbeat is suppressed if either database or photo transfer fails
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Confirmed account and transfer decisions after independent review:
- Keep the complete nightly workflow running as the postgres OS user: pg_dump, local pruning, rsync and heartbeat. Keep the script root-owned and use a dedicated postgres-owned Storage Box SSH key with pinned host verification. No root orchestration, personal david account or additional service account is needed.
- Finish each dump locally before transferring it; do not stream directly to the Storage Box. A failed transfer leaves a valid local dump available to retry.
- Accept that a postgres OS compromise exposes the transfer key and writable mirror. Independently managed Storage Box snapshots are the protection against deletion of that mirror; configure and verify them before considering the backup setup complete.
- The existing implementation already follows these decisions. Remaining work is human provisioning and live transfer, missed-heartbeat and restore verification as documented in infra/README.md.

Retention and execution order confirmed with David: finish the local dump successfully, prune local backups using the existing policy, then rsync -a --delete to the Storage Box. Do not introduce a separate remote pruning job. Send the Better Stack success heartbeat only after all stages succeed. Keep the task ready-for-human pending provisioning and live verification; this confirmation does not verify any acceptance criteria.

Updated account decision: use the main Storage Box account, not a sub-account, for initial provisioning and SSH-key authorization. Earlier sub-account setup instructions are superseded. Align infra/README.md setup examples before provisioning. Other pending human setup and live verification remain unchanged.

Photo scope supersedes the earlier database-only implementation: resolve production UPLOADS_DIR and postgres read access, split remote destinations into database/ and photos/, update script/docs and failure-path tests, then return to ready-for-human for provisioning and live verification. Preserve existing off-site dumps during layout migration. Earlier edenflowers/ root-level rsync examples are superseded.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented the nightly dump/prune/rsync/Better Stack script, production-only SSH setup with a dedicated postgres key and pinned host key, vault examples, setup/restore instructions, and local failure-path tests. Verified: 3 unittest tests (including each failing stage), ShellCheck on rendered production/staging scripts, ansible-lint, ansible-playbook site.yml --syntax-check, and git diff --check. No production provisioning or transfers performed. The encrypted vault currently contains none of the four required vault_backup_* settings. Acceptance criteria remain unchecked pending live verification.

Implemented uploaded-photo backups and the main-account decision. Production mirrors completed dumps to edenflowers/database/ and /opt/<project>/images/uploads/ to edenflowers/photos/, with --delete scoped to each child directory. Both transfers must succeed before the heartbeat. Confirmed the compose mount maps the source to UPLOADS_DIR; provisioning uses 0755 directories and the upload callback sets files to 0644, allowing postgres reads without changing ownership. Updated vault example and setup/restore docs, including safe migration from the old root-level destination and non-atomic DB/photo recovery caveat. Verified 4 unittest tests using Ansible Python, including real local rsync deletion/isolation and missing-source behavior; rendered scripts pass sh -n and ShellCheck; ansible-lint, playbook syntax-check and git diff --check pass. System python3 lacks Jinja, so tests used /opt/homebrew/Cellar/ansible/14.4.0/libexec/bin/python. No production provisioning or transfers performed; acceptance criteria remain unchecked pending live verification.

Production verification on 2026-10-27: latest remote dump edenflowers_store_prod_20261027T082043.dump is 805631 bytes. Read-only rsync -acni --delete checks for database and photos returned no differences; all 10 uploaded photo files match. Local tests verify heartbeat suppression if either transfer fails. Script comments explain failure/retention/snapshot/heartbeat intent without changing behavior. Remaining: configure and verify 10 daily snapshots after backups, heartbeat delivery and missed-heartbeat alerts, and database/photo restores including a deleted photo from snapshot. Launching manually from /home/david exposed find working-directory permissions; launching from /tmp succeeded.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 06:04

---

Human setup remaining: add the Storage Box sub-account username/hostname, independently verified SSH host key, and Better Stack heartbeat URL to the vault; configure heartbeat email alerts and Storage Box snapshots; provision and authorize the generated public key; verify a successful transfer, missed-heartbeat alert, and restore. See infra/README.md.

---

author: @claude
created: 2026-10-27 06:57

---

Rsync approach reconfirmed. Existing local pruning controls mirror retention; no additional backup tool or remote retention job is needed. Remaining human setup and snapshot/transfer/alert/restore checks are unchanged.

---

author: @claude
created: 2026-10-27 07:00

---

David deferred the sub-account. Supply the main Storage Box account username/hostname in the vault and authorize the dedicated postgres key on that account. No directory isolation is claimed. Status remains ready-for-human.

---

author: @claude
created: 2026-10-27 07:00

---

Uploaded photos added by David. Reopened for agent changes because the implemented database-only script does not yet satisfy this scope. Main-account setup remains deferred to human provisioning after code changes.

---

author: @claude
created: 2026-10-27 07:05

---

Ready for human provisioning: configure main-account vault settings, independently verified host key, heartbeat alerts and snapshots; authorize postgres transfer key; ensure separate database/ and photos/ remote directories (pause any old root-level mirror before layout migration); verify existing photo read permissions, both nightly copies, missed-heartbeat alert, and database/photo restores including a deleted photo recovered from snapshot. See infra/README.md.

---

author: @claude
created: 2026-10-27 08:28

---

Updated snapshot policy to the latest 10 daily snapshots. Database and photo transfer criteria are checked based on production checksum verification; failure suppression is covered by local tests. Heartbeat/alert criterion remains unchecked. Status stays ready-for-human for remaining checks.

---

author: @claude
created: 2026-10-27 14:07

---

David confirmed TASK-81 complete on 2026-10-27, including heartbeat alerts.

---
<!-- COMMENTS:END -->
