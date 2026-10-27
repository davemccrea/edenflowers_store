# Translation review queue

Working follow-up to the [27 October audit](../../docs/research/translation-audit-2026-10-27.md).
The audit is a historical snapshot; its Weblate handoff is superseded by the
[Git workflow](README.md#editorial-review-in-git).

## Entry identity and review evidence

For T/S findings, the audit's [coverage ledger](../../docs/research/translation-audit-2026-10-27-coverage.csv)
contains each affected language, domain, context and exact English source under
`finding_ids`. Use that tuple to find the current entry; line numbers and entry
ordinals are not identifiers. Recheck current text before acting.

Receipt findings now refer to `receipts.po`, with empty context:
R01 = `Total`; R02 = `Gross` and `Net`; R03 = `VAT` and `VAT rate`;
R04 = `Delivery` and `Delivery fee`.

The initial corrections below are AI-reviewed only. No native review or Jennie
approval is asserted. When resolving an item, record language, exact source and
context, accepted/rejected wording, reviewer/date and reviewed Git revision.
Keep native language review and Jennie's approval of intended meaning separate.
Optional suggestions may be rejected without changing usable copy.

## Findings

| ID | Language | Current disposition / next reviewer |
| --- | --- | --- |
| T01 | sv, fi | Applied `Relaterad information` / `Lisätietoja`; native heading review remains. |
| T02 | sv | Applied `får du gärna höra av dig`; native review remains. |
| T03 | sv | Applied compound `caféutrymme`, surrounding voice preserved; native review remains. |
| T04 | fi | Applied `Tälle kurssille ilmoittautuminen on päättynyt.`; native review remains. |
| T05 | fi | Native editor: delivery fee label. |
| T06 | sv, fi | Jennie + native editors: order entered for a customer, not an own/bespoke-only order. |
| T07 | sv | Jennie: canonical bouquet size; coordinate database-managed names. |
| T08 | fi | Native editor: natural course/funeral/wedding page titles. |
| T09 | fi | Native editor: align the shop's Finnish address. |
| T10 | sv, fi | Native editors: saving a card does not settle an unpaid order. |
| T11 | sv, fi | Native editors: change deadline before delivery/pickup. |
| T12 | sv, fi | Jennie + native editors: bouquet style and personal-service intent. |
| T13 | fi | Native editor: explicitly enter the email verification code. |
| T14 | fi | Jennie + native editor: canonical subscription terminology. |
| T15 | sv, fi | Jennie: couple versus sender in wedding emails; then native editors. |
| T16 | fi | Native editor: email polish preserving payment meaning. |
| T17 | fi | Developer exception recorded for three exact recipient constructions; native review remains. |
| T18 | fi | Developer exception recorded for one exact email recipient construction; native review remains. |
| S01 | en | Developer: clarify future charge date; Swedish/Finnish already express future tense. |
| S02 | sv, fi, en | Jennie: actual wedding products and price meaning; then align languages. |
| S03 | fi | Native florist/editor + Jennie: funeral tone and product scope against Swedish intent. |
| S04 | en, sv, fi | Jennie + developer: cancellation wording versus committed bouquets/deadline. |
| S05 | sv, fi | Developer + native editors: fulfillment labels must cover pickup where applicable. |
| S06 | sv, fi | Jennie + native editors: order/booking acceptance versus payment. |
| R01 | sv | Applied `Totalt`, matching checkout; native review remains. |
| R02 | sv | Accountant + native editor: gross/net labels. |
| R03 | fi | Accountant + native editor: VAT terminology. |
| R04 | fi | Developer + native editor: general versus home-only delivery labels. |

## Remaining coverage

- Cinder dependency alignment added 15 untranslated admin-only entries per
  language. Translate these after customer-facing review; they currently fall
  back to English and are reported by `mix gettext.stats`.
- Read-only review of database-managed products, courses, categories and
  fulfillment options; local seeds do not represent production wording.
- Browser/layout review of Finnish and Swedish checkout, subscriptions and
  bookings, including long labels and accessibility text.
- Rendered receipt PDF review after receipt changes. Render email previews in
  all three languages after email changes.

Privacy route translations remain a coordinated URL/redirect decision; current
fallbacks are explicitly retained in `check-exceptions.json`.
