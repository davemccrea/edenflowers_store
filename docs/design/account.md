# Surface brief — /account

Mode: **Operate**. Route: `/account` (`EdenflowersWeb.Account.AccountLive`).

## Direction contract

**THESIS.** The account page is the shop's counter ledger, not a dashboard. It refuses the SaaS
settings template — no tabs, no sidebar, no cards, no coloured status pills — and answers three
questions in one scroll: what you bought, what you booked, what you hear from me.

**OWN-WORLD.** DESIGN.md's voice split holds, with one stated departure. Warm oat paper; Crimson
Text for what the shop says — the page title and the three section names — and Open Sans for
everything the tables hold: references, course names, dates, statuses, totals. The departure:
DESIGN.md sets product names and prices in serif, but inside a row they are ledger data rather than
display type, and the shipped cart already reads them that way (`cart/line_items.ex` sets
`product_name` in the inherited sans). Serif names belong to the product grid, where the name is
the composition. Crimson Text also ships no `tnum`, so a serif total could not align its decimal
points down a column even if the rule were followed. Hairline rules separate the sections and the
table rows; no card, no fill, no badge. References, dates and totals set in tabular numerals. The
honey underline appears on the receipt link and the two exit links, nowhere else.

**STORY.** A signed-in customer recognises an order by its date and a plain-language status
("Delivered 14 Sep"), opens its receipt in one click, checks whether a course seat is held, flips
one switch for email, and leaves.

**FIRST VIEWPORT.** `h1` "Account" at `page-title`. Beneath it the identity line — name in serif,
email under it at `/70` — with "Sign out" as a text link, right-aligned from `sm`. Rule. "Orders"
at `section-title`, then Date, Reference, Status, Total (right-aligned, tabular) and Receipt. The
ordered date leads because that is what a customer recognises; the reference is the key they quote
when they phone, not the one they scan by. Rule. "Courses" in the same idiom: Course, Location,
When, Status. Rule. "Newsletter": one checkbox that saves on change, with a polite "Saved" in a
height-reserved live region. The primary action is the receipt link inside the table; the page has
no page-level CTA, by design.

**BELOW `sm`.** Three visible columns is the ceiling: Status carries the longest strings in all
three languages ("Ready to collect today" is 143px, "Noudettavissa tänään" 143px) and a fourth
column leaves it 82px. So Reference and Receipt ride under the date, and Location rides under the
course name, each at `/70`. Measured at 360px, not assumed.

**FORM.** Stacked single-column ledger. Shaped directly rather than dealt: the composition was
specified by the user across two exchanges (three sections, then "a simple table, with a link to
receipt for paid orders, with friendly status"), which new-work.md excludes from the concept-seed
roll. No seed key — `concept-seed` is not present in this install of the launcher.

**FINISH.** unreviewed and undocumented is unfinished; this build ends with the finish review, the
verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Notes

- Courses has no data source yet: nothing in the app calls `register_for_course`, so every user
  sees the empty state until `/courses` ships a registration flow. The section is built for rows
  and reads as intentional while empty.
- Status strings are deliberately plain-language and never claim an outcome the data does not
  support: a pending order whose fulfillment date has passed shows the scheduled date, not
  "Delivered".
