# Customer Reminders

Status: needs-triage
Parked: 2026-10-10. Approach sketched in conversation, not yet broken into issues.

## Problem

A customer who orders flowers for a birthday or for Mother's Day has to remember to come back next year. The shop has no way to bring them back at the moment they need flowers, and they may order elsewhere instead.

A signed-in customer should be able to save the dates they buy flowers for and get an email a few days before each one, with a link straight into the store.

## Decisions

1. **The shop's special days stay in code.**
   `Edenflowers.Fulfillment.KeyDates` keeps its code-defined list. Moving it to the database, so the florist could edit it, isn't worth it yet. The list has barely changed since May 2026 (Christmas Eve was the only removal), a code change is cheap, and the database version needs a resource, a form for the date rules, translated names in the database, and a database read inside the bulk week and weekday toggles (`SetWeek`, `SetWeekday`, `CalendarViewModel`). Revisit if the florist asks to add a day or wants their own one-off days.

2. **Reminders are their own resource, scoped to one customer.**
   This is the separate customer-scoped resource the `KeyDates` moduledoc already anticipates. Each reminder is one of two kinds:
   - **A shop special day**, stored by its key atom (`:mothers_day`). The atoms are stable names, so the reminder doesn't break when the list is edited, and the date is resolved each year through `KeyDates.for_year/1`.
   - **A personal date**: a month, a day and a label ("Mum's birthday"). There's no year, because it repeats every year.

   A reminder for 29 February fires on 28 February in non-leap years.

3. **A daily Oban cron job sends the emails.**
   `Oban.Plugins.Cron` is already configured, with an empty crontab. The job finds every reminder whose next occurrence is the configured number of days ahead, in Helsinki time (`Expressions.HelsinkiToday`), and enqueues one email per reminder. The email uses the existing `Edenflowers.Email` templates. It states the occasion and the date and links into the store, so the delivery date can be picked straight away.

4. **The customer manages reminders on the account page.**
   They can add a reminder from the list of shop special days or as a personal date, and remove one. That's the whole UI for v1; there's no editing, so they remove and re-add.

5. **Every reminder email has a one-click way to stop it.**
   It links to the account page and has a signed link that removes that reminder without signing in. These are service emails the customer asked for, not marketing, so they don't depend on `newsletter_opt_in`.

6. **A reminder's label is personal data about someone else.**
   "Anna's birthday" names a third party. Reminders are deleted with their user. Policies only let the owner read or change their reminders. Admin pages don't list them.

## Open questions

- **How much notice?** One fixed lead time for everyone (5 days?) or per reminder. Fixed is simpler and matches the delivery cut-off. The delivery-windows spec may have a bearing on this.
- **Email language.** `User` has no locale attribute. Either store one (taken from the session when the reminder is created) or send in the language of the customer's last order.
- **Adding from an order.** On the order confirmation page, offer "Remind me next year" with the date and the recipient's name prefilled. This is the cheapest way to get reminders saved, and it may matter more than the account page.
- **Guests.** Reminders need an account. Customers check out as guests today, and the order already upserts a user (`UpsertUserAndAssignToOrder`), so a guest could become a user by saving a reminder.

## Deferred until needed

- Letting the florist edit the shop's special days from admin (see decision 1).
- SMS reminders.
- Storing the recipient's address on the reminder to prefill checkout. Add if customers ask, since it's more personal data to look after.
- Reminders for one-off dates that don't repeat.
