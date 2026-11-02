# Translation review queue

Working follow-up to the 27 October audit. The audit report was a historical
snapshot and has been removed; its Weblate handoff is superseded by the
[Git workflow](README.md#editorial-review-in-git).

## Entry identity and review evidence

For T/S findings, find the current entry by language, domain, context and exact
English source; line numbers and entry
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
| T19 | sv, fi | Home hero subtitle `Bouquets made fresh on delivery day[, from %{price}].` (storefront, no context): AI-drafted `Färska buketter gjorda på leveransdagen` / `Tuoreet kimput tehtyinä toimituspäivänä`, 29 Oct 2026; Jennie (sv meaning) and native fi review remain. |
| T20 | sv, fi | Privacy policy processors (storefront, no context) `Scaleway sends our emails, such as sign-in codes and order confirmations.` and `MailerLite sends the newsletter. It stores newsletter subscribers' contact details, language and purchase statistics, and nobody else's.`, replacing the Brevo line, plus `Updated 31 October 2026.`: AI-drafted from the reviewed Brevo wording, 31 Oct 2026; legal meaning (Jennie) and native sv/fi review remain. |
| R05 | sv, fi | Invoice PDF labels (receipts, no context), from `Invoice` to `Virtual barcode` in `InvoiceLabels`: AI-drafted, 2 Nov 2026. Native sv/fi review and Jennie (sv meaning) remain. |
| T21 | sv, fi | Invoice email (emails, no context), from `Invoice %{number} for your order for %{date}` to `If anything on it looks wrong, just reply to this email.` in `invoice.text.eex`: AI-drafted, 2 Nov 2026. Labels follow R05 (`Förfallodag`, `Mottagare`, `Er referens` / `Eräpäivä`, `Saaja`, `Viitteenne`), but the body uses `du`/`sinä` like the other emails, while `Er referens` addresses the company. Finnish subjects avoid case suffixes on the date and course (`Lasku %{number}: tilauksesi %{date}`). Native sv/fi review and Jennie (sv meaning) remain. |
| R06 | sv, fi | Credit note PDF labels (receipts, no context) in `InvoiceLabels`: `Credit note`, `Credit note number`, `Credited`, `Reason`: AI-drafted, 2 Nov 2026, as `Hyvityslasku`, `Hyvitetään` / `Kreditnota`, `Krediteras`. Accounting terms (hyvityslasku, kreditnota) and the verb forms need native sv/fi review; Jennie (sv meaning) remains. |
| T22 | sv, fi | Credit note email (emails, no context), `Invoice %{number} is cancelled` to `If anything is still to pay, I'll send you a new invoice.` in `credit_note.text.eex`: AI-drafted, 2 Nov 2026. The body says `peruttu`/`makulerat` for cancelled, plainer for a consumer than `hyvitetty`/`krediterat`, while the attachment is `Hyvityslasku`/`Kreditnota`; check the two read as one story. Native sv/fi review and Jennie (sv meaning) remain. |
| T23 | sv, fi | Invoice reminder (emails, no context), `A reminder about invoice %{number} for your order for %{date}`, `A reminder about invoice %{number} for %{course}` and `Just a friendly reminder that it was due on %{date}, and I haven't seen the payment yet. If you've already paid, thank you, and please ignore this email.` in `Email.invoice/2` and `invoice.text.eex`: AI-drafted, 2 Nov 2026, as `En påminnelse om faktura %{number} …` / `Muistutus laskusta %{number}: …` and `… den skulle betalas senast %{date} …` / `… lasku erääntyi %{date} …` (the fi date carries its weekday's -na form). The second sentence reuses the Payment reminder's `If you've already paid…` wording. Tone should stay a gentle nudge (Finnish customers expect to pay after delivery); native sv/fi review and Jennie (sv meaning) remain. |
| R07 | sv, fi | Monthly report receivables sheet headings (admin, `accounting report`): `Invoice number`, `Due date`, `Buyer`, `Invoice amount`, `Unpaid at month end`: AI-drafted, 2 Nov 2026, as `Fakturanummer`, `Förfallodag`, `Köpare`, `Fakturabelopp`, `Obetalt vid månadens slut` / `Laskun numero`, `Eräpäivä`, `Ostaja`, `Laskun summa`, `Maksamatta kuun lopussa`. The sheet itself is named `Kundfordringar` in code. The accountant reads the Swedish; check the terms with them. |
| T24 | sv, fi | Cancellation charge in the Order/Booking cancelled emails (emails, no context), `I've kept %{amount} as a cancellation charge.`, `There's a cancellation charge of %{amount}.`, `There's a cancellation charge of %{charge}, and %{amount} of it is still to pay.`, `I'll send you an invoice for it.` and `I'll be in touch about how to pay it.` in `cancellation_charge.text.eex` and `Templates.collect_line/1`: AI-drafted, 2 Nov 2026, as `avbokningsavgift` / `peruutusmaksu`. Orders are `avbeställd` in Swedish, so an order might want `avbeställningsavgift`; one shared string uses `avbokningsavgift` for both. Read against the course terms' `Efter det behålls %{fee} % av priset.` so the charge sounds like the same rule, and keep it warm, not like a penalty. Native sv/fi review and Jennie (sv meaning) remain. |
| R08 | sv, fi | Cancel drawer and booking drawer (admin, no context): `Cancellation charge (€)`, `Cancellation charge` (replacing `Kept`) and the hint `Total %{total}, paid %{paid}. You keep the charge whether or not it was paid. …`: AI-drafted, 2 Nov 2026. `står kvar att få betalt` / `jää perittäväksi` for "left to collect" need native review. |
| T25 | sv, fi | Invoice, cancellation and booking emails true for every state (emails, no context), AI-drafted 2 Nov 2026: the Invoice email's `My invoice for the cancellation charge for your order for %{date} is attached.` / `… for your booking on %{course} on %{date} is attached.`, the part-paid reminder `Just a friendly reminder that it was due on %{date}, and %{amount} of it is still to pay. Thank you for what you've paid so far.` with the labels `Invoice amount` / `Still to pay` (`Fakturabelopp` / `Laskun summa` as R07, `Kvar att betala` / `Maksettavaa jäljellä` as `Left to pay`); the cancelled emails' plurals `I'll cancel my earlier invoice and send you a new one for it.`, `My earlier invoice already asks for it, so please pay that one.`, `My earlier invoice asks for %{amount} of it, and I'll send you an invoice for the rest.` and `I'll cancel my earlier invoice, so you don't need to pay it.` (`makulerar` / `peruutan`, as T22's credit note email; Swedish says `för avgiften` where English says "for it"); and `My invoice %{number} is due on %{date}.` / `… was due on %{date}.` with `I'll send you an invoice for the rest[ after delivery / after you've collected your order].` in the order and course payment lines (fi dates carry the weekday's -na form). Plus the course terms for an unpaid booking (storefront, no context, read only in the Booking confirmed email): `Cancel at least %{days} days before the course at no cost.`, `After that, %{fee}% of the price is charged.`, `After that, the full price is charged.` as `utan kostnad` / `debiteras` and `veloituksetta` / `veloitetaan`; read them against the paid terms (`full återbetalning`, `behålls`) so they sound like one policy. Native sv/fi review and Jennie (sv meaning, cancellation policy) remain. |
| R09 | sv, fi | Invoice facts (receipts, no context) in `InvoiceLabels`: `Late payment interest`, printed beside the rate (`8,00 %`), replacing the `Late payment interest according to the Interest Act.` sentence, and `Course date`, a course booking's date of supply: AI-drafted, 2 Nov 2026, as `Viivästyskorko` / `Dröjsmålsränta` (as on Zervant's invoices) and `Kurssipäivä` / `Kursdatum`. Native sv/fi review and Jennie (sv meaning) remain. |
| R10 | sv, fi | Receipt PDF (receipts, no context) in `ReceiptLabels`: the payment row `Bank transfer, invoice %{number}` as `Banköverföring, faktura %{number}` / `Tilisiirto, lasku %{number}`, and the closing line once an order is handed over or a course held, `Questions? Just reply to the email this came with, or write to info@edenflowers.fi.` as `Frågor? Svara gärna på mejlet du fick kvittot med, eller skriv till info@edenflowers.fi.` / `Kysyttävää? Vastaa sähköpostiin, jonka mukana sait kuitin, tai kirjoita osoitteeseen info@edenflowers.fi.`: AI-drafted, 2 Nov 2026. The receipt can also be downloaded rather than emailed, so the address is the fallback. Native sv/fi review and Jennie (sv meaning) remain. |
| R11 | sv, fi | Invoice totals (receipts, no context) in `InvoiceLabels`, printed with a negative amount: `To be invoiced later` as `Faktureras senare` / `Laskutetaan myöhemmin`, and `Not charged after cancellation` as `Debiteras inte efter avbokning` / `Ei veloiteta peruutuksen jälkeen`: AI-drafted, 2 Nov 2026. The sv one says avbokning, which fits courses; orders are avbeställda, as noted in T24. Native sv/fi review and Jennie (sv meaning) remain. |

## AI SEO copy follow-up — 28 October 2026

AI-reviewed by the coding assistant on 2026-10-28; native review and Jennie's
editorial approval remain outstanding. These edits preserve the existing service
and pricing policy, not new delivery or wedding commitments. Domain: `storefront`;
context: empty.

- Source: `I also provide wedding flowers outside Vaasa. Travel is quoted separately.`
  - Swedish: `Jag gör också bröllopsblommor utanför Vasa. Resan offereras separat.`
  - Finnish: `Teen hääkukkia myös Vaasan ulkopuolelle. Matkat hinnoittelen erikseen.`
- Source: `Fresh flowers by Jennie at Eden Flowers in Vaasa: bouquets, flower subscriptions, wedding and funeral flowers. Free delivery within %{km} km of Minimossen on selected bouquets.`
  - Existing Swedish/Finnish descriptions retained, replacing literal `5` with
    `%{km}`. The new source ending at `funeral flowers.` uses the same translated
    introduction without the free-delivery sentence when no free radius exists.
    Review preserves the selected-bouquet restriction; terminology T14 is unchanged.
- Source: `Wedding flowers in Vaasa and Korsholm: bridal bouquets, decoration and flower arches designed by Jennie at Eden Flowers.`
  - Existing translations retained without `Priser och tidigare bröllop.` /
    `Hinnat ja aiemmat häät.` because the public price list remains hidden.
- The existing `Saturdays in particular fill up quickly, as I can only take on a limited number of weddings each Saturday. Most couples book 9–12 months ahead.`
  entry and translations are reused unchanged on the wedding page.

## Email receipt and timing cleanup — 3 November 2026

AI-reviewed by Codex on 2026-11-03. Domain: `emails`; context: empty.
The user approved adding order identification and removing payment/fulfillment
timing mismatches. Native Swedish/Finnish review and Jennie's approval of the
exact translations remain outstanding. No payment deadlines or cancellation
terms changed.

Follow-up AI review by Codex on 2026-11-03: the user approved the exact English
`I'll send your invoice separately.` and the amount-specific outstanding-payment
wording. These replace `Payment is by invoice.` and `Payment is still due.`
after fulfillment. The translations below reflect those edits; native review
and Jennie's approval remain outstanding.

| English source | Swedish draft | Finnish draft |
| --- | --- | --- |
| `Booking %{reference}: %{course}, %{date}` | `Bokning %{reference}: %{course}, %{date}` | `Varaus %{reference}: %{course}, %{date}` |
| `Order %{reference} for %{date}` | `Beställning %{reference} för %{date}` | `Tilaus %{reference}, %{date}` |
| `I'll send your invoice separately.` | `Jag skickar din faktura separat.` | `Lähetän laskusi erikseen.` |
| `There's %{amount} left to pay.` | `Det återstår %{amount} att betala.` | `Maksettavaa on vielä %{amount}.` |
| `The payment for your order for %{date} (%{product}) didn't go through.` | `Betalningen för din beställning för %{date} (%{product}) gick inte igenom.` | `Tilauksesi (%{product}, %{date}) maksu ei onnistunut.` |
| `Your receipt from Eden Flowers · %{reference}` | `Ditt kvitto från Eden Flowers · %{reference}` | `Kuittisi Eden Flowersilta · %{reference}` |

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
