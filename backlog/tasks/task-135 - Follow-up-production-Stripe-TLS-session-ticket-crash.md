---
id: TASK-135
title: Follow up production Stripe TLS session-ticket crash
status: needs-triage
assignee: []
created_date: '2026-10-27 08:34'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: bug
ordinal: 268000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Determine whether the production TLS crash needs mitigation so Stripe payment checks remain reliable.

**Why:** A failed Stripe connection can delay recording a customer payment; recurring failures could also disrupt checkout or refunds.

Reported at 2026-10-27 07:30:00.651366Z in Edenflowers.Orders.Workers.ReconcilePayment.perform/1. Error 11: https://edenflowers.fi/admin/errors/11

Observed stack: SSL 11.5 tls_client_ticket_store.get_tickets/4 raises TryClauseError during a Stripe TLS handshake with session_tickets: :auto. Dockerfile currently pins OTP 28.3; Hackney 4.9.1 enables automatic session tickets by default. The precise cause has not been reproduced or verified.

Current decision: monitor rather than apply an immediate workaround. No application changes have been made. Reconciliation runs every ten minutes; the failed job has max_attempts 1, but still-eligible records can be scheduled again.

Follow up recurrence and whether affected payments subsequently reconciled. If mitigation is warranted, evaluate Stripe-only hackney_opts: [ssl_options: [session_tickets: :disabled]], retaining certificate and hostname verification. This disables TLS session resumption for new connections, with potential latency/CPU overhead; pooled connections remain reusable. Alternatively, identify and verify an upstream OTP fix.

Open for triage: recurrence, customer impact, affected payment recovery, and whether to monitor, disable session tickets, or upgrade OTP.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Check recurrence and confirm whether the affected payment subsequently reconciled.
- [ ] #2 Record a decision to continue monitoring or apply a verified mitigation/upstream fix, including supporting evidence.
<!-- AC:END -->
