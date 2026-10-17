# Booking Payment Links

Summary: Send a course booking a link to pay what it owes online, as custom orders already can
Status: ready-for-agent

## Problem

A booking Jennie adds by hand says "Payment is taken at the course". Some customers would rather pay beforehand, and a booking can owe money after a seat is added back or a payment is undone. Today the only way to collect is at the course or outside the app. Orders already have a payment link (`/pay/:token`, ADR 0002); payment-balance left links for bookings out of scope as a way of taking money, which stays per resource.

## Decisions

1. **The link is the shop's own payment page, not a Stripe Payment Link.** Like an order's: a tokened page with Stripe's Payment Element, paying a PaymentIntent whose metadata names the booking. Stripe Payment Links are a separate Stripe product with their own checkout and price objects; using one would bypass `Payments.complete/1`, the receipt and the balance, and need a Price per amount owed.

2. **A confirmed booking owing money can have a link.** `CourseRegistration` gets `payment_link_token` (unique identity, sensitive), an `open_payment_link` update reusing `Orders.Changes.OpenPaymentLink` (move it to `Edenflowers.Payments.Changes` since both use it), `payment_link_open?` (`not is_nil(payment_link_token) and balance > 0 and status == :confirmed`), and a `by_payment_link_token` read. A cancelled booking has no open link.

3. **Paying the link records a payment on the booking, which is already confirmed.** `confirm_payment` is for checkout: it refuses a confirmed booking (`NotAlreadyPaid`) and expects the full `amount`. A new `record_link_payment`, like the order's: records a Stripe payment of what arrived, clears the PaymentIntent if it's the one paid, emails the receipt again (`ScheduleConfirmationEmail`). `Payments.complete_payable/4` for a booking routes a confirmed booking to it and a pending one to `confirm_payment`, as orders split on `state`. `expected_amount/1` for a booking with `balance` loaded is the balance, so the PaymentIntent charges what's owed, not the booking's total. Recording a payment by hand already cancels the open PaymentIntent (`CancelOpenPaymentIntent`).

4. **The customer pays on a page in the booking's language.** `/courses/pay/:token`, in the courses feature, showing the course, date, seats, what's been paid and what's owed, then the Payment Element. It reads the booking only through its token and shows nothing else about it. Paid, it says so and stays readable. Modelled on `PayLive`; not merged with it, since what it shows differs.

5. **The link is in addition to paying at the course, not instead.** The quick payment form on the booking row stays, and an added booking still says payment is taken at the course. Whichever comes first settles the booking: recording a payment by hand cancels the link's open PaymentIntent, and a settled booking's link reads as paid. Paying part online leaves the rest for the quick form, prefilled with the balance.

6. **Jennie sends it from the booking.** In the booking's ⋯ menu on the courses page, shown while the booking owes money: "Email payment link" (opens the link, then emails it in the booking's locale) and "Copy payment link". The email is a new course email: the course, what's owed, the link. Sending again confirms first, as on the order page.

## Out of scope

- Payment links on pending bookings. A pending booking is a seat hold during checkout; it either pays there or lapses.
- SMS or WhatsApp message links, which the order page has. Bookings have no phone number.
- Reminders for unpaid links.
