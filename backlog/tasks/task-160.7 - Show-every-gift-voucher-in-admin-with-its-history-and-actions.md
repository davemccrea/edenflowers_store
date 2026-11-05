---
id: TASK-160.7
title: Find and look after a gift voucher from its order
status: done
assignee: []
created_date: '2026-11-05 19:53'
updated_date: '2026-11-05 20:41'
labels: []
dependencies: []
parent_task_id: TASK-160
type: feature
ordinal: 339000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** When a customer calls about a voucher, Jennie needs to find it, see what's left and what it was spent on, and help them: give it more time or send it again.

Decisions (grilled 2026-11-05, folded into the order page in a Ponytail review the same day):
- **No vouchers page.** A voucher is looked after from the order that sold it. Admin search already finds the recipient and the buyer; it also matches the voucher's code (Order.matches?).
- **Gift voucher card** on the order: also shows what's left, and the voucher's :voucher payments (date, amount, link to the order or booking they paid or were handed back from). That list is the voucher's history; nothing is added to the order log.
- **Change last day:** an action on GiftVoucher that takes a later expires_on, allowed only while the voucher isn't cancelled or used up, validated with the same calculations the card reads. No note and no history: one person runs the shop, and the card shows the current date.
- **Resend:** add gift_voucher_sold as an email kind in the order's email drawer (EmailDrawer), so its address is editable and the send shows in the order's log.

**Not now:** a list of all vouchers or outstanding balances (a report sheet when the accountant asks), a PDF download (TASK-160.3 adds it for vouchers sold in the shop), a history of last-day changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Searching admin orders by a voucher's code finds the order that sold it
- [x] #2 The order's Gift voucher card shows what's left and every payment the voucher made or took back, each linked to its order or booking
- [x] #3 Jennie can move a voucher's last day later from its card, and an earlier date is refused
- [x] #4 Jennie can resend a voucher's email from its order's email drawer to an address she chooses
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: Replaced the /admin/vouchers list, detail page and voucher log with additions to the order page, after a Ponytail review.

2026-11-05 (done): Order.matches? finds a whole voucher code typed any way. The Gift voucher card shows what's left and each :voucher payment linked to its order or booking, and Change last day (GiftVoucher :change_last_day, validated by last_day_changeable? against the stored date, so a stale page can't shorten it). A paid voucher order's menu offers Resend gift voucher in place of the receipt: Order :email_gift_voucher sends the voucher email with both PDFs to an editable address, logged as 'Gift voucher emailed' with orders_versions.email_to. Spending part of a voucher exposed a crash in the order menu's cancel reason, now 'Some of the voucher is spent'. Checked in the browser.
<!-- SECTION:NOTES:END -->
