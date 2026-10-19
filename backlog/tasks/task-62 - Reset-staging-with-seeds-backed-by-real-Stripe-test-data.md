---
id: TASK-62
title: Reset staging with seeds backed by real Stripe test data
status: ready-for-agent
assignee: []
created_date: '2026-10-19 08:02'
labels:
  - spec
  - developers
  - admin
dependencies: []
priority: medium
type: chore
ordinal: 131000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reset staging to the seeded shop with real Stripe test data behind every seeded payment, so money flows can be tested there end to end.

**Why:** Seeded payments carry made-up Stripe ids (`pi_seed_…`, `cus_seed_…`, `pm_seed_…`), so on staging every Stripe refund, payment link, subscription charge, the reconcile cron and the monthly report's Stripe sheet fail or come out empty on seeded records. Each money feature (goodwill refunds, the course payment drawer, the monthly report) then needs test orders made by hand first.

### Problem

`just db-seed staging` already runs `priv/repo/seeds.exs` on the staging server, but nothing the seeds record exists in Stripe. There is also no single command to start staging over from an empty database.

### Decisions

1. **The seeds create the Stripe objects themselves, behind a flag.** No second script that patches ids afterwards: it would describe the same data twice and drift. Where `seeds.exs` invents a Stripe id today, it creates the real test-mode object when the flag is on and keeps the made-up id when it's off, so local seeding stays offline and unchanged.
   - Online order payments and paid course bookings: a confirmed PaymentIntent for the payment's amount with `pm_card_visa`, its id on the `Payment`.
   - Refunds seeded "as the webhook would" (Elin's booking, the order called off and refunded in full, the made-smaller order): a real Stripe refund on that PaymentIntent, recorded through the same `record_stripe_refund` path.
   - The part-paid order: a real PaymentIntent for its balance, recorded through the same path the payment link uses.
   - Online subscriptions: a real customer with `pm_card_visa` attached, so the occurrence job can charge it on staging. The seeds' comment about keeping the job away from the fake ids changes to match.
   - Pekka's abandoned booking stays without a PaymentIntent.
   Stripe calls go through `Edenflowers.External.StripeAPI` where it has the function; add one there if it doesn't.

2. **The flag reaches the rpc node.** Staging seeds run through `bin/edenflowers rpc` inside the app container, so an environment variable on the ssh command doesn't reach them. The recipe sets the flag inside the rpc expression (for example `Process.put(:seed_stripe, true)` before `Code.eval_file`), and the seeds read it from there or from `SEED_STRIPE=1` locally.

3. **Seeding with Stripe refuses a live key.** If the flag is on and the configured secret key doesn't start with `sk_test_`, the seeds stop before writing anything.

4. **Stripe can't be backdated.** Every Stripe object is dated the day of seeding while seeded `Payment`s keep their relative dates, so the Stripe sheet only matches the current month. Accepted; note it in a seeds comment.

5. **One recipe resets staging.** `just staging-reset` drops and recreates the staging database, migrates it and seeds it with Stripe on, after a confirmation prompt naming staging. Read phoenix-ansible for how staging's Postgres and app container run rather than probing the server. Wiping Stripe stays manual (Stripe has no API for it): the recipe prints a reminder to use "Delete all test data" in the Dashboard first (or recreate the sandbox and update staging's keys and webhook secret).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With the flag on, every seeded Stripe payment, refund and subscription customer exists in Stripe test mode with matching ids and amounts
- [ ] #2 Without the flag, local seeding makes no Stripe calls and produces the same data as today
- [ ] #3 Seeding with the flag refuses a key that isn't sk_test_ before writing anything
- [ ] #4 just staging-reset empties, migrates and seeds staging with Stripe on, after a confirmation, and reminds to wipe Stripe test data first
- [ ] #5 On a reset staging, a seeded order can be refunded through Stripe from the admin and the current month's Stripe sheet lists the seeded charges and refunds
<!-- AC:END -->
