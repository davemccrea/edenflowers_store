# Map when each email is sent

Write a map of every email the app sends: what makes it go out, under which
conditions, its subject and who it appears to come from. The reader is Jennie,
the florist who runs the shop, not a developer. `just email-map` runs this
prompt and puts every rendered email after your map, so keep to the map.

## How to find it

Read the code; don't guess from names. Trace each email from where it is
built back to what sets it off:

1. `lib/edenflowers/email.ex` builds every email. Each public function is one
   email (some pick between subjects). `from_address()` sends under Jennie's
   name; `automated_from_address()` under "Eden Flowers".
2. Find each builder's callers: the changes in `lib/edenflowers/*/changes/`
   and the Oban workers in `lib/edenflowers/*/workers/`. Note where a sender
   picks one email over another (a balance, a date, a photo, who cancelled).
3. Find the resource actions that use those changes, in
   `lib/edenflowers/orders/order.ex`, `subscription.ex`,
   `lib/edenflowers/courses/course_registration.ex` and
   `lib/edenflowers/payments/payable.ex`. Read each `where:` condition and each
   argument's default, such as whether "email the customer" starts ticked.
4. For an email queued through an AshOban trigger (`oban do triggers`), read
   its `scheduler_cron` and `where expr(...)` for scheduled ones, and the
   comment above it.
5. For an action Jennie runs by hand, find the button in
   `lib/edenflowers_web/features/admin/` so you can say where she clicks.
6. Don't miss the emails outside orders, bookings and subscriptions: the
   newsletter, the wedding enquiry, sign-in and email change codes, the shop
   notices to Jennie and the error alert.

## What to write

Markdown only, with no preamble or closing remarks. Start with
`# When each email is sent`, then one table per group: Orders, Course
bookings, Subscriptions, and Everything else. Columns:

| Email | Sent when | Subject | From |

- **Email**: the email type name used in `lib/edenflowers/email/previews.ex`
  (the first element of each preview tuple), so the reader can find its
  rendered versions further down.
- **Sent when**: what happens, in the shop's terms ("Jennie cancels an order
  and keeps Email the customer ticked, which it is by default"). Say what's
  attached. Give schedules in Finnish time ("daily at 07:00").
- **Subject**: the English subject, with placeholders in braces, such as
  `{day}`, `{course}` or `{ref}`. Give each variant.
- **From**: **Jennie** or **Eden Flowers**.

Say once, above the tables, which emails send a hidden copy to Jennie's
records inbox. After the tables, add a short `## Worth knowing` list for
anything surprising: two emails with the same subject, defaults that differ
between similar actions, an email that never fires. Leave it out if there's
nothing.

Write plainly. No code identifiers, file paths or function names in the
output. Never use em dashes: use a comma or a colon, or split the sentence.
