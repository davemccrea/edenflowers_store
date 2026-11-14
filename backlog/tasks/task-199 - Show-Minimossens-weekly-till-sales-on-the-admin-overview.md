---
id: TASK-199
title: Show Minimossen's weekly till sales on the admin overview
status: done
assignee: []
created_date: '2026-11-14 09:06'
updated_date: '2026-11-14 12:00'
labels:
  - admin
  - spec
dependencies: []
references:
  - lib/edenflowers/expenses/actions/import_invoice_emails.ex
  - lib/edenflowers/external/fastmail_api.ex
  - docs/papra.md
  - lib/edenflowers_web/features/admin/overview_live.ex
  - 'https://github.com/fltoss/spreadsheet'
priority: medium
type: feature
ordinal: 364000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie sells flowers and refurbished shop items through Minimossen's shared till. Every Monday Stormossen (`noreply@stormossen.fi`, subject "Winpos raportti") emails two `.XLS` reports for the previous Monday-Sunday week. One covers product group 3 (Eden Flowers kukat). The other covers groups 6 (Eden ruukut), 7 (Eden lelut) and 66 (Eden - kirjat ja lehdet). Show these on the Overview so Jennie can see how she is selling from week to week.

**Why:** today she only sees till sales once a month, as screenshots in Maria Wikberg-Jatta's "Minimossen <month>" email, and has nothing to compare weeks with.

## Proposal (not yet grilled)

**Import, like invoice emails (see `docs/papra.md`):**
- A Fastmail filter moves the Winpos emails into a `Winpos` folder.
- An Oban job every 15 minutes (production only, like `ImportInvoiceEmails`) downloads each `.XLS` attachment, reads it with the Hex package `spreadsheet` (calamine, prebuilt binaries), saves it, and moves the email to `Winpos/Importerade`.
- Docker: the deploy workflow builds a `linux/amd64` image on Debian trixie, and `spreadsheet` 0.7.1 ships a prebuilt `x86_64-unknown-linux-gnu` binary (plus aarch64 and musl). `mix deps.compile` in the builder stage downloads it from GitHub and checks it against the package's checksum file. No Rust toolchain is needed, and the running container needs no network for it.
- If a file doesn't match the expected layout, the job fails and alerts. It never saves a guess.
- `.XLS` is the only format Winpos sends. No Claude: it can't read `.xls` without a code-execution sandbox, and this layout never changes.

**Report layout (checked with `spreadsheet` 0.7.1 on the 2.-8.11.2026 reports):**
- Sheet `Sheet1`. One row reads `"Pvm: 2.11.2026 - 8.11.2026"`.
- A header row `["Koodi", "Nimitys", nil, "Määrä", "Myynti", ...]` is followed by one row per group, e.g. `["6", "6 Eden ruukut", nil, 54.0, 221.4, ...]`, and ends with `Yhteensä`.
- Myynti is gross sales including VAT, read as a float. Round it to cents as a Decimal.

**Storage:** an Ash resource with one row per week and product group (week start, group code, name, quantity, gross sales), unique on (week, group), so a re-import overwrites instead of duplicating.

**Overview card "Minimossen till":** last week's gross sales against the week before, split into Flowers (group 3) and Shop (6, 7, 66), plus stacked bars for the last 12 weeks. It sits next to TASK-166's "Last week" row. It shows gross sales only, not the payout: commission rates changed in 2026 and corrections (Korjaus) only appear in the monthly sheet, so the monthly email stays the record of what she's paid.

## Open questions for grilling
- Does production's Fastmail mailbox receive the Winpos emails, or does Jennie need to forward them?
- Can old Winpos emails be imported to backfill earlier weeks?
- Where on the Overview does the card go, and what are the Flowers/Shop labels in Swedish?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Winpos emails filed in the Fastmail folder `Winpos` are imported and moved to `Winpos/Importerade`
- [x] #2 Each week's gross sales are stored per product group, and importing the same report again overwrites instead of duplicating
- [x] #3 A report that doesn't match the expected layout fails the job with an alert and saves nothing
- [x] #4 The Overview shows the latest week's Minimossen sales against the 8-week average, split by product group, each in its own colour, with the last 12 weeks as stacked bars
- [x] #5 Both 2.-8.11.2026 reports are test fixtures
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Grilled 2026-11-14: the Winpos emails already arrive in the shop's Fastmail mailbox. The card is its own card under This month. Built without TASK-166, so the dependency is dropped. Old reports backfill by dragging their emails into `Winpos`.

Built as the `Edenflowers.Minimossen` domain: `WeeklySales` (one row per week and product group, upserted), an hourly scheduled `import_reports` action, and `recent_weeks`, which ends at the latest week imported so a report that lands on Sunday shows at once. Glossary: "till sale" means a Custom Order, so this is called Minimossen sales.

Before it works in production: create the Fastmail folders `Winpos` and `Winpos/Importerade`, and a filter moving mail from `noreply@stormossen.fi` into `Winpos`.

Reviewed 2026-11-14: the card compares the latest week with the average of the 8 weeks before it rather than with the week before, since one week is too noisy to judge by. Weeks without a report are left out of the average. The average is drawn as a light dashed line across the bars. A last line gives the year's total so far, by ISO week year, labelled with the weeks it covers (e.g. "This year, weeks 34–45") until older reports are backfilled.

Changed 2026-11-14: the card splits by Winpos product group instead of Flowers and Shop. Each group gets a row, named as Winpos names it, and its own colour in the bars; the rows double as the chart's legend.

Reviewed again 2026-11-14: a week without sales was left out as if unreported. Each report now saves 0 for every group its `Tuoteryhmät:` filter cells cover (e.g. `6 - 7`) that has no line, named by its code, so a closed week counts in the average and the card can end on it. A report without those cells fails as a changed layout. `WinposReport.from_rows/1` lets tests check the layout errors with plain rows.

Changed 2026-11-14: the card is `EdenflowersWeb.Admin.MinimossenCard`, a LiveComponent, shown on the Overview and full width on its own page, `/admin/minimossen` (under Finances), where each bar is labelled on large screens ("v. 34"). The year's-total line is gone, since the Year view gives the same total. The card loads once per visit rather than on every Overview refresh, so a report imported meanwhile shows after a reload.
<!-- SECTION:NOTES:END -->
