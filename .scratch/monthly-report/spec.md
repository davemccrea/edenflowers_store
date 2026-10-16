# Monthly Accounting Report

Status: ready-for-agent

## Problem

Each month Jennie sends her accountant the shop's income and expenses. The data is already in the app (payments on orders, course bookings, expenses extracted from receipts in Papra), but there is no way to get it out in one piece. The accountant needs income split by VAT rate for the VAT return, and a copy of every receipt behind the expenses.

## Decisions

1. **Jennie downloads one zip for a chosen month from the expenses page.**
   No new page: the existing admin expenses page gets an `<input type="month">` and a download button, a plain form that GETs an admin-only controller route (for example `/admin/accounting/2026-09`). The controller sends `kirjanpito-YYYY-MM.zip` with `send_download/3`. Jennie forwards it herself. No automatic emailing in v1.

   ```
   kirjanpito-2026-09.zip
   ├── raportti-2026-09.xlsx
   └── kuitit/
       ├── 001_2026-09-03_Kukkatukku.pdf
       └── 002_2026-09-11_Adobe.pdf
   ```

2. **The spreadsheet is one `.xlsx` with three sheets: Tulot (income), Kulut (expenses) and Stripe.**
   Real number and date cells, so Finnish Excel shows no separator or decimal-comma problems. Adds the `elixlsx` dependency. The zip is built in memory with Erlang's `:zip`; no other dependency.

3. **The shop reports VAT on a cash basis, so everything counts by when the money moved, in Helsinki time.**
   Jennie uses cash-basis VAT (*maksuperusteinen ALV*): a sale counts in the month the money arrives, a purchase in the month it's paid. This is the same rule as `SalesSummary` and ADR 0002: a payment belongs to the month of its `paid_at`, a refund to the month it went out. Month boundaries are Helsinki midnight, as in `SalesSummary.helsinki_midnight_utc/1`.
   Expenses count by when they were paid: a new nullable `paid_on` date on `Expense`, falling back to `date` (the receipt or invoice date) when empty. Card receipts are paid on their date, so `paid_on` only needs filling for a supplier invoice paid later. Jennie sets it when correcting the expense: add it to the `correct` action's accepted fields and to the expense detail form. Not extracted by the LLM, since a receipt or invoice doesn't say when it was paid. Generate the migration from the resource.

4. **Income is split by VAT rate, net and VAT shown separately, and this report is the only sales record.**
   The VAT return reports domestic sales separately for each rate (25.5%, 13.5%, 10%), so Vero expects sales at different rates to be easy to tell apart.
   Every sale, over-the-counter ones included, ends up as an order in the admin. So every payment method (Stripe, Zettle, MobilePay, cash, Zervant) counts in the totals, and Zettle, Zervant and MobilePay are only ways of getting paid. The accountant must not also book sales from Zettle's or Zervant's own reports, or those sales are counted twice.
   - **Order payments:** one row per `Payment` per VAT rate. The order's `vat_breakdown` snapshot (`Orders.VatRow`: rate, base, vat, gross) gives the proportions; each payment's amount is split across the rates by each rate's share of the order's gross. Most orders have one payment for the whole order, so the split equals the breakdown. Rounding: round each rate's share to the cent and put any leftover cent on the largest rate, so the rows always sum to the payment amount.
   - **Course bookings:** one row per confirmed `CourseRegistration` paid in the month (`paid_at`), with its `amount` and `tax_rate`.
   - **Columns:** payment date, reference (`order_reference` or the registration's `reference`), source (order or course), payment method, VAT rate, net, VAT, gross.
   - **Below the rows:** totals per VAT rate (net, VAT, gross), which are the figures the accountant copies into the VAT return.

5. **Every expense paid in the month is included, with a reviewed column.**
   The accountant sees which rows Jennie has checked rather than having unreviewed ones silently left out. Expenses with neither `paid_on` nor `date` can't be placed in a month and are left out; the expenses list already sorts undated ones to the top, so Jennie sees them there.
   - **Columns:** row number, paid date, invoice date, vendor, vendor VAT number, category, description, currency, total, VAT, net (total minus VAT), reviewed (kyllä/ei), receipt file.
   - **Currency:** SEK expenses stay in SEK, with the currency column. No conversion to EUR.

6. **Each expense's receipt PDF goes in the zip under `kuitit/`.**
   The accountant has no Papra account, so a Papra id or link would mean nothing to them. Download with `PapraAPI.fetch_document/2`. The filename is `<row number>_<date>_<vendor>.pdf`, with the vendor cut down to ASCII letters, digits and `-`. The zero-padded row number matches the sheet row and makes every name unique. The expense row's "receipt file" column holds that filename. If any download fails, the whole download fails with an error flash and Jennie tries again, so the accountant never gets a zip with receipts missing.

7. **The report is built in a plain module, the web layer only serves it.**
   `Edenflowers.Accounting.MonthlyReport.build(year, month)` returns `{:ok, filename, zip_binary}` or an error. No Ash domain, resource or generic action: it only reads, and the admin-only route is the access check. It reads with `authorize?: false`, as `SalesSummary` and `Payments` do for internal reads. Sheet headings and filenames are in Finnish, as the accountant reads Finnish; the expenses page's new copy goes through gettext like the rest of the admin.

8. **A Stripe sheet carries fees and payouts, so the accountant can match Stripe deposits in the bank.**
   Stripe pays out net of fees, in batches. List the month's balance transactions (created in the month, Helsinki boundaries) through `StripeAPI`, auto-paginating: a new function on the existing client, behind `StripeAPI.impl()` so tests can stub it.
   - **Columns:** date, type (charge, refund, payout, fee, adjustment), description, gross, fee, net, payout id.
   - **Below the rows:** total fees (booked as an expense) and total paid out to the bank.
   These rows are not sales; sales come from the Tulot sheet.

   If Stripe can't be reached, the whole download fails, as for receipts in decision 6.

## Open questions

- **Tell the accountant this report is the sales record.** They should book sales only from the Tulot sheet, and Stripe fees and payouts from the Stripe sheet. Until the Zettle sheet exists, they take Zettle fees and payouts from Zettle's own report, but never Zettle's or Zervant's sales.
- **How the accountant takes receipts.** Many Finnish accounting systems (Procountor, Netvisor, Fennoa) have their own receipt inbox. If the accountant prefers that, the zip may only need the spreadsheet.

## Deferred until needed

- **A Zettle sheet.** Zettle pays out net of fees, like Stripe. Read the month's payment fees and payouts from Zettle's Finance API, with the same columns and totals as the Stripe sheet.
  - **New client:** `Edenflowers.External.ZettleAPI`, using Zettle's self-hosted app login (assertion grant with an API key). Two new secrets, the client id and the API key. Jennie creates the key in her Zettle account; only the account owner can. Check the Finance API's endpoint, scope and transaction type names (`PAYMENT_FEE`, `PAYOUT`) against developer.zettle.com, as third-party descriptions disagree.
  - **Missing-order check:** Zettle's own total of card payments in the month, the total of order payments recorded as `:zettle`, and the difference. A difference means a Zettle sale with no order, missing from the VAT return (ADR 0004). A file download can't carry a flash, so a non-zero difference redirects back to the expenses page with a flash stating it and a "download anyway" link (`?force=true`). A payment recorded after midnight on the month boundary can cause a small false difference.
- Emailing the report automatically each month (Oban cron). Add if Jennie forgets to send it.
- Building the zip in a background job. Synchronous is fine for tens of receipts a month; move to Oban if the download gets slow.
- MobilePay and Zervant data. Zervant invoices are paid into the bank in full, and Zervant has no public API anyway. MobilePay on Jennie's own number is assumed to pay in full too; if it's a business account that deducts fees, its Report API needs accounting-partner keys, so ask the accountant first.
- Converting SEK expenses to EUR.
- Refunds of course bookings. Cancelling a registration records no refund today, so there is nothing to report.

## Sources

- [Vero: pienyrityksen maksuperusteinen ALV](https://vero.fi/yritykset-ja-yhteisot/verot-ja-maksut/arvonlisaverotus/pienyrityksen-maksuperusteinen-alv/)
- [Vero: when to file and pay VAT](https://vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/when-to-file-and-pay/)
- [Vero: laskutusvaatimukset arvonlisäverotuksessa](https://www.vero.fi/syventavat-vero-ohjeet/ohje-hakusivu/48090/laskutusvaatimukset-arvonlisäverotuksessa/)
- [Stripe: reporting and reconciliation](https://docs.stripe.com/plan-integration/get-started/reporting-reconciliation)
- [Zettle: create an API key (self-hosted app)](https://developer.zettle.com/docs/get-started/user-guides/create-app-credentials/create-app-credentials-for-self-hosted-app/create-an-api-key)
- [Zettle Finance API migration guide](https://github.com/iZettle/api-documentation/blob/master/finance-api/finance-api-migration-guide.md)
- [Ageras: does Zervant integrate with other software](https://ageras.com/us/support/360054605611-does-zervant-integrate-with-other-software)
