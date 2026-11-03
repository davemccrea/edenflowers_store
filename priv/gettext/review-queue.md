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
| R02 | sv | Accountant + native editor: gross/net labels. 3 Nov 2026: the VAT breakdown's `Gross` column changed from `Totalt` to `Inkl. moms`, AI-drafted, so it no longer repeats the `Total` (`Totalt`) heading beside it and pairs with `à-pris inkl. moms`; `Net` stays `Netto`. |
| R03 | fi | Accountant + native editor: VAT terminology. 3 Nov 2026: the receipt and invoice VAT column (`receipts`, `VAT`) now reads `ALV` instead of `Vero`, matching the glossary. |
| R04 | fi | Developer + native editor: general versus home-only delivery labels. |
| T19 | sv, fi | Home hero subtitle `Bouquets made fresh on delivery day[, from %{price}].` (storefront, no context): AI-drafted `Färska buketter gjorda på leveransdagen` / `Tuoreet kimput tehtyinä toimituspäivänä`, 29 Oct 2026; Jennie (sv meaning) and native fi review remain. |
| T20 | sv, fi | Privacy policy processors (storefront, no context) `Scaleway sends our emails, such as sign-in codes and order confirmations.` and `MailerLite sends the newsletter. It stores newsletter subscribers' contact details, language and purchase statistics, and nobody else's.`, replacing the Brevo line, plus `Updated 31 October 2026.`: AI-drafted from the reviewed Brevo wording, 31 Oct 2026; legal meaning (Jennie) and native sv/fi review remain. |
| R05 | sv, fi | Standalone invoice PDF labels (`receipts`, empty context) in `InvoiceLabels`: `Invoice`, `Invoice number`, `Invoice date`, `Due date`, `Your reference`, `Due on this invoice`, `Payment details`, `Account (IBAN)`, `Reference number`, `Amount` and `Virtual barcode`, plus the shared line/VAT headings. New `Unit price incl. VAT` is AI-drafted as `à-pris inkl. moms` / `Verollinen à-hinta` (3 Nov 2026, replacing `Styckepris inkl. moms` / `Yksikköhinta sis. alv` to match the à-pris / à-hinta pattern of the receipt and of laskutys, a Finnish invoice template); the column prints the supplied VAT-inclusive unit price, including sub-cent precision. Finnish `Invoice date` is AI-drafted as `Laskupäivä` (3 Nov 2026, replacing `Laskun päivämäärä`) to match the receipt's `-päivä` date labels (`Tilauspäivä`, `Toimituspäivä`, `Noutopäivä`) and `Eräpäivä`. Each ordinary booking-advance or remainder invoice prints only its own lines and VAT. Native sv/fi review and Jennie (sv meaning) remain; date/interest labels are R09. Removed purchase deductions are retired under R11. |
| T21 | sv, fi | Standalone invoice email (`emails`, empty context) in `Email.invoice/2` and `invoice.text.eex`: subject `Invoice %{number}` and new body `My invoice %{number} is attached.` (`Min faktura %{number} finns bifogad.` / `Laskuni %{number} on liitteenä.`), then the invoice amount, due date and frozen payment details, ending `If anything on it looks wrong, just reply to this email.` AI-drafted, 2 Nov 2026. Labels retain `Förfallodag`, `Mottagare`, `Er referens` / `Eräpäivä`, `Saaja`, `Viitteenne`; check company-reference wording beside the personal du/sinä voice. Subjects referring to an order date or course, whole-purchase/part-of-total claims and automatic cancellation-charge introductions are removed and retired. Native sv/fi review and Jennie (sv meaning) remain. |
| R06 | sv, fi | Full credit-note PDF labels (`receipts`, empty context) in `InvoiceLabels`: `Credit note`, `Credit note number`, `Credited`, `Reason`, `Date`, and the original `Invoice number` / `Invoice date`. AI-drafted, 2 Nov 2026, including `Hyvityslasku`, `Hyvitetään` / `Kreditnota`, `Krediteras`. The document prints original billed lines and exactly negative frozen gross, base and VAT per rate; it reverses a whole issued invoice with zero net recorded money. Check accounting terms, verb forms and the shared VAT/unit-price labels (R05). Paid/part-paid corrections go to the accountant. Native sv/fi review and Jennie (sv meaning) remain. |
| T22 | sv, fi | Standalone credit-note email (`emails`, empty context): subject `Invoice %{number} is cancelled`; body `I've cancelled invoice %{number} from %{date}, so you don't need to pay it. My credit note %{credit_note} is attached for your records.` and `If anything is still to pay, I'll send you a new invoice.` in `credit_note.text.eex`. AI-drafted, 2 Nov 2026. Existing `peruttu`/`makulerat` consumer wording and attachment names `Hyvityslasku`/`Kreditnota` need to read as one story. This is a full unpaid standalone invoice reversal, with no purchase cancellation or automatic replacement relationship. Native sv/fi review and Jennie (sv meaning) remain. |
| T23 | sv, fi | Standalone manual invoice reminder (`emails`, empty context): current subject `A reminder about invoice %{number}` (`En påminnelse om faktura %{number}` / `Muistutus laskusta %{number}`), plus `Just a friendly reminder that it was due on %{date}, and I haven't seen the payment yet. If you've already paid, thank you, and please ignore this email.` in `Email.invoice/2` and `invoice.text.eex`. AI-drafted, 2 Nov 2026. Review the gentle tone, weekday/date forms and the part-paid variant in T25. Removed reminder subjects naming an order date or course are retired; this reminder follows the standalone invoice due date. Native sv/fi review and Jennie (sv meaning) remain. |
| R07 | sv, fi | Monthly report (`admin`, context `accounting report`): receivables headings `Invoice number`, `Due date`, `Buyer`, `Invoice amount`, `Unpaid at month end` remain AI-drafted as `Fakturanummer`, `Förfallodag`, `Köpare`, `Fakturabelopp`, `Obetalt vid månadens slut` / `Laskun numero`, `Eräpäivä`, `Ostaja`, `Laskun summa`, `Maksamatta kuun lopussa`. New receipt-source `invoice` is `faktura` / `lasku`; these rows are standalone invoice receipts alongside ordinary shop sales. The sheet name is `Kundfordringar`. Payment-method `Bank transfer` (`admin`, empty context) is `Banköverföring` / `Tilisiirto`; the former `Bank transfer (invoice)` label is retired, since purchase transfers remain usable independently. Accountant + native sv/fi review remain; no native approval is asserted. |
| T24 | sv, fi | Purchase cancellation-charge emails (`emails`, empty context): current `I've kept %{amount} as a cancellation charge.`, `There's a cancellation charge of %{amount}.`, `There's a cancellation charge of %{charge}, and %{amount} of it is still to pay.` and `I'll be in touch about how to pay it.` in `cancellation_charge.text.eex` / `Templates.collect_line/1`. AI-drafted, 2 Nov 2026, as `avbokningsavgift` / `peruutusmaksu`; check order avbeställd versus course avbokning, warmth and agreement with course cancellation terms. `I'll send you an invoice for it.` and all earlier-invoice replacement/payment/cancellation promises are removed and retired. Cancellation retains an ordinary purchase balance; it creates no invoice. Native sv/fi review and Jennie (sv meaning) remain. |
| R08 | sv, fi | Cancel drawer and booking drawer (admin, no context): `Cancellation charge (€)`, `Cancellation charge` (replacing `Kept`) and the hint `Total %{total}, paid %{paid}. You keep the charge whether or not it was paid. …`: AI-drafted, 2 Nov 2026. `står kvar att få betalt` / `jää perittäväksi` for "left to collect" need native review. |
| T25 | sv, fi | Current state-dependent email wording, AI-drafted 2 Nov 2026: standalone part-paid reminder (`emails`, empty context) `Just a friendly reminder that it was due on %{date}, and %{amount} of it is still to pay. Thank you for what you've paid so far.` with `Invoice amount` / `Still to pay` (`Fakturabelopp` / `Laskun summa`, `Kvar att betala` / `Maksettavaa jäljellä`). Course payment instruction `Please pay at the course.` is newly drafted `Betala på kursen.` / `Maksa kurssilla.`; bank-transfer arrangements instead use `I'll be in touch about how to pay it.` Admin booking hint (`admin`, empty context) `Record the bank transfer here once it arrives.` is `Registrera banköverföringen här när den kommer.` / `Kirjaa tilisiirto tähän, kun se saapuu.` Review these with `Bank transfer` in R07. Retain native review of unpaid course terms (`storefront`, empty context): `Cancel at least %{days} days before the course at no cost.`, `After that, %{fee}% of the price is charged.`, `After that, the full price is charged.` against paid terms. Removed purchase/cancellation-charge invoice introductions, earlier-invoice plural plans, invoice due-date attribution in purchase emails and promises to invoice the rest are retired. Native sv/fi review and Jennie (sv meaning, cancellation policy) remain. |
| R09 | sv, fi | Standalone invoice facts (`receipts`, empty context): `Late payment interest`, beside frozen `8,00 %`, remains AI-drafted `Dröjsmålsränta` / `Viivästyskorko`. New `Date of supply` is `Leveransdatum` / `Toimituspäivä`, required to issue an invoice since 3 Nov 2026 (AVL § 209 e); Jennie can supply her own description for an advance/supply date. Both are invoice-owned information. The old purchase-derived `Course date` label and `Late payment interest according to the Interest Act.` sentence are retired. Native sv/fi review and Jennie (sv meaning and date/advance intent) remain. |
| R10 | sv, fi | Receipt PDF (`receipts`, empty context): current bank-transfer method label `Bank transfer` is `Banköverföring` / `Tilisiirto`, with no invoice attribution. The old `Bank transfer, invoice %{number}` payment row and dual purchase/invoice receipt attribution are removed and retired. Keep native review of the closing line once an order is handed over or a course held: `Questions? Just reply to the email this came with, or write to info@edenflowers.fi.` as `Frågor? Svara gärna på mejlet du fick kvittot med, eller skriv till info@edenflowers.fi.` / `Kysyttävää? Vastaa sähköpostiin, jonka mukana sait kuitin, tai kirjoita osoitteeseen info@edenflowers.fi.` The address remains the fallback for downloaded receipts. Native sv/fi review and Jennie (sv meaning) remain. |
| R12 | sv, fi | Part-paid invoice PDF (`receipts`, empty context): under `Due on this invoice`, a resent part-paid invoice prints `Paid` as a negative amount and `Still to pay`, which the payment details and barcode then ask for. AI-drafted 3 Nov 2026 as `Betalt` / `Maksettu` and `Kvar att betala` / `Maksettavaa jäljellä`, matching the T25 reminder email. `Betalt` (neuter, the sum paid) differs from the status adjective `Betald` in `emails`. Native sv/fi review and Jennie (sv meaning) remain. |
| R13 | sv, fi | Invoice payment details (`receipts`, empty context): new `Payee` before `Account (IBAN)`, printing the frozen seller name, as on a Finnish bank transfer. AI-drafted 3 Nov 2026 as `Mottagare` / `Saaja`, the words laskutys (a Finnish invoice template) uses. Native sv/fi review and Jennie (sv meaning) remain. |
| R14 | sv, fi | Invoice and credit-note lines (`receipts`, empty context) now print the VAT-exclusive unit price, `Unit price net`, before `Unit price incl. VAT`, as AVL § 209 e asks of a full invoice. Swedish `Unit price net` changed 3 Nov 2026 from `à-pris netto` to `à-pris exkl. moms` to pair with `à-pris inkl. moms`; the receipt uses it too. Finnish stays `Veroton à-hinta`. Accountant: confirm the VAT-exclusive price, rounded to cents by the same rule as order receipts, meets the requirement. Since 3 Nov 2026 invoices, like receipts, take the VAT out once per rate, so a unit price times its quantity may differ by a cent from the breakdown's net. Native sv review and Jennie (sv meaning) remain. |
| R11 | sv, fi | Retired purchase-linked invoice-total wording: `To be invoiced later` (`Faktureras senare` / `Laskutetaan myöhemmin`) and `Not charged after cancellation` (`Debiteras inte efter avbokning` / `Ei veloiteta peruutuksen jälkeen`) are removed from source/catalogs and require no approval for current UI. Standalone invoices print only their own billed lines/VAT, with no whole-purchase totals, earlier-advance deductions or cancellation remainder rows. Current total/unit-price/VAT terminology still needs native/accountant review under R05/R06; no native approval is asserted. |

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
