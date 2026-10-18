---
id: TASK-11
title: 'Download a month''s income, expenses and receipts for the accountant'
status: ready-for-human
assignee: []
created_date: '2026-10-17 00:38'
updated_date: '2026-10-18 21:04'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: feature
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
One monthly download of income and expenses, with receipts, for the accountant

**Why:** Jennie gathers each month's income, expenses and receipts for the accountant by hand, though the data is all in the app. One download saves her that and gives the VAT return its figures.

### Problem

Each month Jennie sends her accountant the shop's income and expenses. The data is already in the app (payments on orders, course bookings, expenses extracted from receipts in Papra), but there is no way to get it out in one piece. The accountant needs income split by VAT rate for the VAT return, and a copy of every receipt behind the expenses.

### Decisions

1. **Jennie downloads one zip for a chosen month from the expenses page.**
   No new page: the existing admin expenses page gets an `<input type="month">` and a download button, a plain form that GETs an admin-only controller route (for example `/admin/accounting/2026-09`). The controller sends `redovisning-YYYY-MM.zip` with `send_download/3`. Jennie forwards it herself. No automatic emailing in v1.

   ```
   redovisning-2026-09.zip
   ├── rapport-2026-09.xlsx
   └── kvitton/
       ├── 001_2026-09-03_Kukkatukku.pdf
       └── 002_2026-09-11_Adobe.pdf
   ```

2. **The spreadsheet is one `.xlsx` with three sheets: Försäljning (sales), Inköp (expenses) and Stripe.**
   Real number and date cells, so Finnish Excel shows no separator or decimal-comma problems. Adds the `elixlsx` dependency. The zip is built in memory with Erlang's `:zip`; no other dependency.

3. **The shop reports VAT on a cash basis, so everything counts by when the money moved, in Helsinki time.**
   Jennie uses cash-basis VAT (*maksuperusteinen ALV*, in Swedish *kontantprincipen*): a sale counts in the month the money arrives, a purchase in the month it's paid. This is the same rule as `SalesSummary` and ADR 0002: a payment belongs to the month of its `paid_at`, a refund to the month it went out. Month boundaries are Helsinki midnight, as in `SalesSummary.helsinki_midnight_utc/1`.
   Expenses count by when they were paid: a new nullable `paid_on` date on `Expense`, falling back to `date` (the receipt or invoice date) when empty. Card receipts are paid on their date, so `paid_on` only needs filling for a supplier invoice paid later. Jennie sets it when correcting the expense: add it to the `correct` action's accepted fields and to the expense detail form. Not extracted by the LLM, since a receipt or invoice doesn't say when it was paid. Generate the migration from the resource.

4. **Income is split by VAT rate, net and VAT shown separately, and this report is the only sales record.**
   The VAT return reports domestic sales separately for each rate (25.5%, 13.5%, 10%), so Vero expects sales at different rates to be easy to tell apart.
   Every sale, over-the-counter ones included, ends up as an order in the admin. So every payment method (Stripe, Zettle, MobilePay, cash, Zervant) counts in the totals, and Zettle, Zervant and MobilePay are only ways of getting paid. The accountant must not also book sales from Zettle's or Zervant's own reports, or those sales are counted twice.
   - **Order payments:** one row per `Payment` per VAT rate. The order's `vat_breakdown` snapshot (`Orders.VatRow`: rate, base, vat, gross) gives the proportions; each payment's amount is split across the rates by each rate's share of the order's gross. Most orders have one payment for the whole order, so the split equals the breakdown. Rounding: round each rate's share to the cent and put any leftover cent on the largest rate, so the rows always sum to the payment amount.
   - **Course bookings:** course money is `Payment` rows like order money (ADR 0002, `TASK-12`), so this sheet reads one table: one row per course `Payment`, at the registration's `tax_rate`.
   - **Refunds:** every refund is recorded, so every refund is a negative row in the month it was made. Order and course refunds are both negative `Payment`s, including an in-person refund on a cancelled order.
   - **Edited orders:** a paid order's `vat_breakdown` is refreshed when it's edited, so an earlier payment is split by the new proportions. This only matters when an edit changes the mix of rates, and only by cents; accepted.
   - **No personal data:** rows carry references, never customer names or emails. The zip leaves the app by email, so keep it that way.
   - **Columns:** payment date, reference (`order_reference` or the registration's `reference`), source (order or course), payment method, VAT rate, net, VAT, gross.
   - **Below the rows:** totals per VAT rate (net, VAT, gross), which are the figures the accountant copies into the VAT return.

5. **Every expense paid in the month is included, with a reviewed column.**
   The accountant sees which rows Jennie has checked rather than having unreviewed ones silently left out. Expenses with neither `paid_on` nor `date` can't be placed in a month and are left out; the expenses list already sorts undated ones to the top, so Jennie sees them there.
   - **Columns:** row number, paid date, invoice date, vendor, vendor VAT number, category, description, currency, total, VAT, net (total minus VAT), reviewed (ja/nej), receipt file.
   - **Currency:** SEK expenses stay in SEK, with the currency column. No conversion to EUR.
   - **Below the rows:** totals of total, VAT and net, one line per currency. Only Finnish VAT is deductible: foreign VAT on a SEK receipt isn't, and EU purchases such as Adobe or Stripe's fees arrive without VAT and are reported by the accountant under reverse charge (*omvänd skattskyldighet*). The vendor VAT number's country prefix (SE, IE) shows them which rows those are.

6. **Each expense's receipt PDF goes in the zip under `kvitton/`.**
   The accountant has no Papra account, so a Papra id or link would mean nothing to them. Download with `PapraAPI.fetch_document/2`. The filename is `<row number>_<date>_<vendor>.pdf`, with the vendor cut down to ASCII letters, digits and `-`. The zero-padded row number matches the sheet row and makes every name unique. The expense row's "receipt file" column holds that filename. If any download fails, the whole download fails with an error flash and Jennie tries again, so the accountant never gets a zip with receipts missing.

7. **The report is built in a plain module, the web layer only serves it.**
   `Edenflowers.Accounting.MonthlyReport.build(year, month)` returns `{:ok, filename, zip_binary}` or an error. No Ash domain, resource or generic action: it only reads, and the admin-only route is the access check. It reads with `authorize?: false`, as `SalesSummary` and `Payments` do for internal reads. Sheet names, headings, filenames and values such as categories and payment methods are in Swedish where possible, using Finland-Swedish accounting terms; Stripe, Zettle, MobilePay and Zervant stay as they are. The report is rendered inside `Gettext.with_locale("sv", ...)`, so it reuses the existing Swedish translations (categories like "Kontorsmaterial", "Konsulttjänster", payment methods like "Kontant") and its new strings get Swedish msgstrs alongside en and fi. The expenses page's new copy goes through gettext like the rest of the admin.

   | English | Swedish |
   |---|---|
   | Sales / Expenses (sheet names) | Försäljning / Inköp |
   | Payment date, Invoice date | Betalningsdag, Fakturadatum |
   | Reference, Source (order, course) | Referens, Källa (beställning, kurs) |
   | Payment method | Betalningssätt |
   | VAT rate, Net, VAT, Gross | Momssats, Exkl. moms, Moms, Inkl. moms |
   | Row number, Vendor, Vendor VAT number | Nr, Leverantör, Leverantörens momsnummer |
   | Category, Description, Currency, Total | Kategori, Beskrivning, Valuta, Totalt |
   | Reviewed (yes, no), Receipt file | Granskad (ja, nej), Kvittofil |
   | Date, Type, Fee, Payout id | Datum, Typ, Avgift, Utbetalnings-id |
   | Charge, Refund, Payout, Fee, Adjustment | Debitering, Återbetalning, Utbetalning, Avgift, Justering |
   | Total per VAT rate, Total fees, Paid out to bank | Summa per momssats, Avgifter totalt, Utbetalt till bank |

   Checked against Vero's Swedish pages: Vero says *momssats* on its rate pages and *skattesats* in its detailed guidance, *kontantprincipen* for cash-basis VAT, and *exklusive skatt* for amounts before VAT. Its legal term for a vendor's VAT number is *mervärdesskattenummer*; *momsnummer* is the everyday short form. Have the accountant glance at the terms on the first report.

8. **A Stripe sheet carries fees and payouts, so the accountant can match Stripe deposits in the bank.**
   Stripe pays out net of fees, in batches. List the month's balance transactions (created in the month, Helsinki boundaries) through `StripeAPI`, auto-paginating: a new function on the existing client, behind `StripeAPI.impl()` so tests can stub it.
   - **Columns:** date, type (charge, refund, payout, fee, adjustment), description, gross, fee, net, payout id.
   - **Below the rows:** total fees (booked as an expense) and total paid out to the bank.
   These rows are not sales; sales come from the Försäljning sheet.

   If Stripe can't be reached, the whole download fails, as for receipts in decision 6.

### Open questions

- **Tell the accountant this report is the sales record.** They should book sales only from the Försäljning sheet, and Stripe fees and payouts from the Stripe sheet. Until the Zettle sheet exists, they take Zettle fees and payouts from Zettle's own report, but never Zettle's or Zervant's sales.
- **How the accountant takes receipts.** Many Finnish accounting systems (Procountor, Netvisor, Fennoa) have their own receipt inbox. If the accountant prefers that, the zip may only need the spreadsheet.

### Deferred until needed

- **A Zettle sheet.** Zettle pays out net of fees, like Stripe. Read the month's payment fees and payouts from Zettle's Finance API, with the same columns and totals as the Stripe sheet.
  - **New client:** `Edenflowers.External.ZettleAPI`, using Zettle's self-hosted app login (assertion grant with an API key). Two new secrets, the client id and the API key. Jennie creates the key in her Zettle account; only the account owner can. Check the Finance API's endpoint, scope and transaction type names (`PAYMENT_FEE`, `PAYOUT`) against developer.zettle.com, as third-party descriptions disagree.
  - **Missing-order check:** Zettle's own total of card payments in the month, the total of order payments recorded as `:zettle`, and the difference. A difference means a Zettle sale with no order, missing from the VAT return (ADR 0004). A file download can't carry a flash, so a non-zero difference redirects back to the expenses page with a flash stating it and a "download anyway" link (`?force=true`). A payment recorded after midnight on the month boundary can cause a small false difference.
- Emailing the report automatically each month (Oban cron). Add if Jennie forgets to send it.
- Building the zip in a background job. Synchronous is fine for tens of receipts a month; move to Oban if the download gets slow.
- MobilePay and Zervant data. Zervant invoices are paid into the bank in full, and Zervant has no public API anyway. MobilePay on Jennie's own number is assumed to pay in full too; if it's a business account that deducts fees, its Report API needs accounting-partner keys, so ask the accountant first.
- Converting SEK expenses to EUR.

### Sources

- [Vero: pienyrityksen maksuperusteinen ALV](https://vero.fi/yritykset-ja-yhteisot/verot-ja-maksut/arvonlisaverotus/pienyrityksen-maksuperusteinen-alv/)
- [Vero: Småföretag kan redovisa moms enligt kontantprincipen](https://vero.fi/sv/foretag-och-samfund/skatter-och-avgifter/momsbeskattning/smaforetag_kan_redovisa_moms_enligt_bet/)
- [Vero: Momssatser](https://vero.fi/sv/foretag-och-samfund/skatter-och-avgifter/momsbeskattning/momssatser/)
- [Vero: Faktureringskraven vid mervärdesbeskattningen](https://vero.fi/sv/Detaljerade_skatteanvisningar/anvisningar/48090/faktureringskraven-vid-merv%C3%A4rdesbeskattningen/)
- [Vero: when to file and pay VAT](https://vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/when-to-file-and-pay/)
- [Vero: laskutusvaatimukset arvonlisäverotuksessa](https://www.vero.fi/syventavat-vero-ohjeet/ohje-hakusivu/48090/laskutusvaatimukset-arvonlisäverotuksessa/)
- [Stripe: reporting and reconciliation](https://docs.stripe.com/plan-integration/get-started/reporting-reconciliation)
- [Zettle: create an API key (self-hosted app)](https://developer.zettle.com/docs/get-started/user-guides/create-app-credentials/create-app-credentials-for-self-hosted-app/create-an-api-key)
- [Zettle Finance API migration guide](https://github.com/iZettle/api-documentation/blob/master/finance-api/finance-api-migration-guide.md)
- [Ageras: does Zervant integrate with other software](https://ageras.com/us/support/360054605611-does-zervant-integrate-with-other-software)
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 21:04

---

Sequential queue verification: TASK-11.1, TASK-11.2, TASK-11.3 and TASK-11.5 are done; TASK-11.4 has all 4 acceptance criteria checked and is ready-for-human. Reviewed the existing Ash reads, admin-only Phoenix download/error flow and Stripe pagination/sheet implementation; no missing agent implementation identified. Verified on main with source .env && mix test test/edenflowers/accounting/monthly_report_test.exs test/edenflowers/external/stripe_api_test.exs test/edenflowers_web/features/admin/expenses_live_test.exs: 28 tests, 0 failures. Blocker: a human must download a month's report on staging (or locally with the test key) and compare the Stripe sheet's rows, fees and payout totals against the Stripe dashboard balance report for the same Helsinki-bounded month, then record the result on TASK-11.4. The first report also needs the accountant's terminology glance and confirmation that sales are booked only from Försäljning, Stripe fees/payouts from Stripe, and Zettle fees/payouts from Zettle's own report without duplicating sales. Keep TASK-11 and TASK-11.4 open until the human verification is recorded. No quick label was present.

---
<!-- COMMENTS:END -->
