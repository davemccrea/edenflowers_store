---
id: TASK-11.2
title: Monthly report download with expenses and receipts
status: ready-for-agent
assignee: []
created_date: '2026-10-17 07:07'
updated_date: '2026-10-18 07:28'
labels: []
dependencies:
  - TASK-11.1
parent_task_id: TASK-11
type: feature
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Gets the download working end to end, so Jennie can send expenses and receipts before the sales and Stripe sheets exist.

### What to build

The end-to-end path: Jennie picks a month on the admin expenses page and downloads a zip holding the spreadsheet, with its Inköp (expenses) sheet, and every receipt PDF. The Försäljning and Stripe sheets come in `TASK-11.3` and `TASK-11.4`. See decisions 1, 2, 5, 6 and 7 in `TASK-11`.

- **Module:** `Edenflowers.Accounting.MonthlyReport.build(year, month)` returns `{:ok, filename, zip_binary}` or `{:error, reason}`. A plain module, not an Ash domain or action; reads use `authorize?: false`.
- **Month boundaries:** Helsinki midnight, as `SalesSummary.helsinki_midnight_utc/1` does. Expenses carry plain dates, so they're filtered by date: an expense is in the month when `paid_on`, or `date` if `paid_on` is empty, falls in it. Expenses with neither are left out.
- **Spreadsheet:** add `elixlsx`. One workbook, `rapport-YYYY-MM.xlsx`, with real date and number cells.
- **Inköp sheet**, sorted by paid date then vendor:
  - Columns: row number, paid date (`paid_on` or `date`), invoice date (`date`), vendor, vendor VAT number, category, description, currency, total, VAT, net (total minus VAT), reviewed (ja/nej), receipt file.
  - Below the rows: totals of total, VAT and net, one line per currency.
  - Headings and category names in Swedish, through gettext (decision 7).
- **Receipts:** fetch each expense's PDF with `PapraAPI.fetch_document/2` and add it as `kvitton/<NNN>_<date>_<vendor>.pdf`. `NNN` is the zero-padded row number; the vendor is cut down to ASCII letters, digits and `-`. The receipt file column holds the same name. If any fetch fails, `build` returns an error; no partial zip.
- **Zip:** built in memory with Erlang's `:zip`, named `redovisning-YYYY-MM.zip`.
- **Route:** an admin-only controller route, for example `GET /admin/accounting/:month` with `month` as `YYYY-MM`. It sends the zip with `send_download/3`. On an error, or a malformed month, it redirects back to the expenses page with an error flash.
- **Expenses page:** an `<input type="month">`, defaulting to the previous month, and a download button in a plain GET form. Copy through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A non-admin gets no report from the route
- [ ] #2 The zip holds `rapport-YYYY-MM.xlsx` and one PDF per expense under `kvitton/`, and each row's receipt file names its PDF
- [ ] #3 An invoice dated in August with `paid_on` in September is in September's report, not August's
- [ ] #4 Expenses with no date are left out
- [ ] #5 A failed Papra fetch gives an error flash and no download
- [ ] #6 Totals per currency equal the sum of their rows
- [ ] #7 Tests build a report from fixtures, with Papra stubbed, and read the sheet back
<!-- AC:END -->
