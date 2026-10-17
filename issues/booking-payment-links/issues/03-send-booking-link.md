# Jennie emails or copies a booking's payment link from the courses page

Status: ready-for-agent
Type: feature

## What to build

Spec decisions 5 and 6.

- In the booking's ⋯ menu, while it owes money: "Email payment link" and "Copy payment link". Emailing opens the link, then sends a new course email (course, what's owed, the link) in the booking's locale; sending again asks first. Copying uses the admin copy button.
- An `email_payment_link` update on `CourseRegistration` that sends the email, recording when it was sent, like the order's `send_order_details_email`.
- New copy, including the email, through gettext with en, fi and sv msgstrs.

## Tests

- The menu items show only on a booking owing money, alongside the quick payment form.
- Recording a payment at the course after sending the link settles the booking, and its link page then reads paid.
- Emailing sends one email to the booking's address, in its locale, with the link; the booking then has an open link.
- Sending again asks to confirm.

## Acceptance criteria

- [ ] Every case above passes
- [ ] The existing suite passes

## Blocked by

- 01, 02
