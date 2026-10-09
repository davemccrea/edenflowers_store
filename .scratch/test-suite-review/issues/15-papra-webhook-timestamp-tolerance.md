# Papra webhook rejects stale timestamps

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (aside)

## What to build

`PapraWebhook` checks the HMAC but never checks `webhook-timestamp`, so a captured delivery can be replayed forever. Reject deliveries whose timestamp is more than 5 minutes from now in either direction, which is the Standard Webhooks default.

## Acceptance criteria

- [ ] A correctly signed delivery with a timestamp older than 5 minutes is rejected
- [ ] A correctly signed delivery with a timestamp more than 5 minutes in the future is rejected
- [ ] A fresh, correctly signed delivery is still accepted

## Blocked by

None - can start immediately
