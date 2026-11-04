---
id: TASK-173.1
title: Pass the Enable Banking keys to production
status: done
assignee: []
created_date: '2026-11-04 17:44'
updated_date: '2026-11-04 17:48'
labels:
  - quick
dependencies: []
parent_task_id: TASK-173
type: chore
ordinal: 332000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the sync can only sign Enable Banking requests in production.

Already in the vault (vault_enable_banking_application_id, vault_enable_banking_private_key as a one-line string with \n escapes). vars.yml maps them and the compose template passes ENABLE_BANKING_APPLICATION_ID and ENABLE_BANKING_PRIVATE_KEY, the key through to_json so its line breaks survive. Commit the infra changes; provision with the first deploy that reads them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 vault.example.yml, vars.yml and the compose template carry both keys
- [x] #2 runtime.exs reads both env vars, and only when both are set
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Vault keys, vars.yml, compose env (key via to_json) and runtime.exs :enable_banking (application_id, private_key), set only when both env vars are.
<!-- SECTION:NOTES:END -->
