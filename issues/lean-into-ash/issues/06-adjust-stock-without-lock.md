# Drop AdjustStock's row lock, or keep it on purpose

Status: needs-triage
Type: refactor

## Problem

`Changes.AdjustStock` reads each tracked variant `FOR UPDATE`, then calls the atomic `adjust_stock`. The atomic update alone already prevents lost updates and keeps stock at 0 or above. The lock and read exist only so `report_oversell?: true` can log when an order takes more than is left.

## Options

- Keep it: the lock makes the oversell log exact, and the sorted lock order already avoids deadlocks. The cost is a read and a lock per tracked size, on orders that rarely have more than one.
- Drop it: call `adjust_stock` through `Ash.bulk_update` on the order's tracked variants, and log an oversell from a plain read beforehand. The log could then miss or misreport an oversell under a race, which is when it matters most.

## Recommendation

Keep it unless profiling says otherwise. Recorded so nobody "simplifies" it without knowing why it's there: add a one-line comment to `adjust/3` saying the lock is for the oversell report.

## Comments
