# Customer email copy review

Reviewed 20 October 2026 using the copy-editing skill, with copywriting for replacement passages.

**Diagnosis B:** Jennie's voice is already present: first person, practical details, short greetings and a personal signature. Preserve it. The job is to make instructions and promises more precise.

Scope: all 15 customer email builders, their 53 exported scenarios, and the distinct rendered wording in English, Swedish and Finnish. Recommendations below use English as the source copy, with specific translation findings. This is an editorial review, not an implementation or a native-speaker certification. The developer error alert is outside the customer catalogue.

The seven passes covered clarity, voice, relevance, evidence, specificity, emotion and barriers to action. For transactional emails, reassurance comes from accurate dates, amounts and next steps. Standard greetings and functional labels do not need to sound unique to Eden Flowers.

## 1. Order confirmation / receipt

**Verdict: light edit.** The subject identifies the receipt and order number. The opening answers when and where the flowers arrive. Keep both, including the pickup, time-window and subscription variants. Keep the cancellation date when cancellation is available.

Replace the shared support sentence:

> Your receipt is attached. If you have a question about your order, reply to this email.

Reason: the same paragraph appears after fulfillment and after the cancellation deadline. “If anything needs changing ... I'll take care of it” suggests every requested change can still be made. A general invitation fits all these states without making the tone defensive.

For subscription receipts, make the account link's scope explicit:

> You can manage your upcoming subscription orders from your account:
> {account_url}

The current order has already been charged; the account sentence should not suggest that pausing automatically reverses it. Keep the actual cancellation rules in the account flow.

**Variants checked:** cancellable, past deadline, fulfilled, specific delivery time, time window, pickup, subscription and missing name. The missing-name greeting works.

## 2. Order details

**Verdict: light edit, with a missing-state check.** Keep “Thank you for your order. Here is what we agreed.” It sounds like a florist following up on a conversation. Keep the item breakdown, recipient, fulfillment information and the separate invoice/pay-on-collection instructions.

For resends, replace “Here is your order as it stands now” with:

> Here are your order details:

This is shorter and also works when Jennie simply resends an unchanged order. “Updated order details” is suitable only when a change is known; `order_details_emailed_at` alone does not prove one happened.

Replace the closing with:

> If you need to change anything, reply and I'll let you know what's possible.

Keep the existing subject. An “Updated” subject would need a genuine edit signal too.

**Variants checked:** first send, resend, edited online order, pickup, partial payment, invoice, pay on fulfillment, free delivery, time window and missing name. Add previews for settled and overpaid orders: “Paid in full” plus “Nothing is left to pay” does not tell an overpaid customer whether a refund is due. Do not claim a refund has happened from a negative balance alone.

## 3. Subscription payment failed

**Verdict: revise first.** The current email reassures the customer that this order still arrives, which is valuable. Keep that immediately after the failed-payment notice. Keep the amount and payment link prominent.

Recommended opening:

> The payment for your next subscription order didn't go through on your saved card.

Remove the speculative explanation about an expired or replaced card. The system does not need to diagnose the decline to explain the next step.

Keep the delivery/pickup-specific reassurance. Replace the paragraph after the payment link with:

> Future subscription orders are on hold. Paying this order restarts your subscription.
>
> You can also update your saved card from your account. Updating it restarts future orders, but you still need to pay this order using the link above:
> {account_url}

This reflects both reactivation paths in `Subscription.replace_card` and `ReactivateSubscription`. The current “until this one is paid” is incomplete: replacing the card also reactivates the subscription without settling the debt.

Close with:

> If you need help with the payment, reply to this email.

Keep the subject, which names the action and order. Avoid “To keep this from happening again”: replacing a card cannot guarantee future payments succeed.

**Variants checked:** delivery and pickup without a name. The pickup email currently calls later orders “deliveries” in all three languages. “Future subscription orders” fixes that.

## 4. Subscription set up

**Verdict: light edit plus clearer timing.** Keep the summary of size, frequency, price, location and first two dates. Keep the explanation that the promotion and card message apply only to the first order.

Use:

> Thank you for starting a flower subscription.

This distinguishes the purchase from a newsletter subscription and removes the unnecessary exclamation mark. Change “Then” to “Next delivery” or “Next pickup” so both dates have explicit labels.

Replace the long account sentence with:

> You can change the size or frequency, update your card, or pause or cancel your subscription from your account:
> {account_url}

The UI supports different rules for different actions. If adding a deadline, scope it to the actions validated by `SubscriptionChangesOpen`:

> To pause or change an upcoming order, make the change at least {days} days before delivery or pickup.

Derive `{days}` from `Subscription.cutoff_days() + 1`, currently five. Do not apply that deadline to changing the card or cancelling the subscription: those actions do not use that validation. The charge notice remains three days before fulfillment.

**Variants checked:** weekly pickup, fortnightly delivery, four-weekly delivery, sizes, discount, message and missing name. Add separate discount-only and message-only scenarios.

## 5. Order fulfilled

**Verdict: keep.** Both subject and opening immediately confirm what happened. The named-recipient version reassures the sender; the pickup version correctly says “collected,” not “ready to collect.”

Keep the thank-you and invitation to reply if something is wrong. Here “I'll take care of it” is a customer-service commitment, not a promise to reverse a cancellation. There is no reason to remove Jennie's warmth everywhere because the phrase is too broad elsewhere.

**Variants checked:** named gift, unnamed gift, non-gift with a name, missing customer name and pickup. No sales CTA needed.

## 6. Order left at door, photo attached

**Verdict: shorten the opening.** The attached photo is the useful detail; keep its mention in the subject and body. Split the long sentence.

Named gift:

> Nobody was home when I delivered your order for {recipient}. The attached photo shows where I left it.

Other orders:

> Nobody was home when I delivered your order. The attached photo shows where I left it.

Keep the existing support line and signature. Do not add “safely” or “securely”: the template does not establish either fact. The sender may not be the recipient, so do not write “you weren't home.”

**Variants checked:** all four gift/name combinations. Swedish and Finnish should use the same two-sentence structure. In Finnish the current named version can read as if the order was handed to Sara before saying nobody was home; the revised structure avoids that ambiguity.

## 7. Order cancelled

**Verdict: retain the factual detail, soften the recovery promise.** Keep the cancellation date, refund amount and known destination. They answer the customer's immediate questions.

Replace the final sentence with:

> If you didn't mean to cancel, reply and I'll help you arrange a new order.

This offers a concrete next step without suggesting a cancelled order or refund can simply be undone.

The exact refund arrival estimates are not established by this repository. Before publishing a revised timing promise, obtain the current payment-provider guidance for the supported payment methods. Until then, a conservative alternative is:

> It may take a few days for the refund to appear.

That is an editorial alternative, not a verified provider timeframe. The strongest factual fallback is to state the refund amount and destination without promising arrival time.

**Translation fix:** Finnish says the order “was due to be delivered.” It also serves pickup orders. Use fulfillment-neutral wording such as “Tilauksesi päivälle {date} on peruttu.” Format the date to fit the sentence rather than reusing a weekday already inflected for another construction. Swedish “annullerad” is more formal than the surrounding “avbeställa”; “avbeställd” would make the register consistent.

**Variants checked:** card, MobilePay, mixed methods and no refund. Add pickup cancellation. A zero refund must not become “You haven't paid”: zero refunded does not establish payment history.

## 8. Course confirmation

**Verdict: keep the structure; separate cancellation information.** The opening confirms one or several places. The date, time and venue are easy to find. Keep the subject and “See you there.”

Put the payment/receipt sentence and cancellation paragraph on separate lines. They currently run together in the rendered email.

Paid, with a fee:

> Your receipt is attached.
>
> To cancel, reply at least 7 days before the course for a full refund. If you cancel later, I keep {fee} as a cancellation fee.

Paid, no fee:

> Your receipt is attached.
>
> If you need to cancel, reply to this email. Please let me know at least 7 days before the course if you can.

The zero-fee implementation retains no late fee, so the existing sentence can imply a refund deadline that the configured fee does not support. A full-refund statement for later cancellations should be agreed with Jennie before making it a customer promise; the narrower replacement above avoids inventing a policy.

Unpaid:

> If you need to cancel, reply to this email. Please let me know at least 7 days before the course if you can.

The code explicitly says an unpaid booking owes no cancellation fee. Do not introduce one. Partial-payment cases require their own review: `balance > 0` includes them, but the current email uses the unpaid wording and omits the fee that can be retained from money already paid.

**Variants checked:** unpaid with/without link, paid with/without fee, multiple seats and missing name. The current fee is per booking and capped by money held; do not multiply it by seats in the copy.

## 9. Course payment link

**Verdict: reorder for clarity.** Keep the subject. Put the amount before the payment link so the customer knows what they are about to pay.

> You have {balance} left to pay for {course}.
>
> Pay online by card or MobilePay:
> {payment_url}
>
> Or pay at the course if you prefer.

Then keep the date and venue, followed by the cancellation paragraph on its own. “Left to pay” works for both unpaid and partially paid bookings.

**Variants checked:** named and unnamed. Add partial-payment coverage and apply the same cancellation distinction as the confirmation email.

## 10. Wedding enquiry copy

**Verdict: keep almost all of it.** The opening explains the next step and clearly distinguishes an enquiry from a booking. “As soon as I can” is preferable to an invented turnaround guarantee.

Keep the subject, the optional-field handling and the explicit distinction between a rough estimate and a quote. That distinction is necessary information, not a rhetorical contrast to remove mechanically.

Add a label before the customer's free-text message:

> Your message:

It currently appears directly after the estimate and can look like text from Jennie. A blank line before “Here's a copy of what you sent” would also separate the acknowledgment from the record.

**Variants checked:** complete and required-fields-only enquiries. Keep the Swedish/Finnish plural address to the couple; it is appropriate to this audience. Do not promise date availability before Jennie has checked it. A precise response-time claim needs her agreed service target.

## 11. Newsletter welcome with discount

**Verdict: add the missing path to purchase.** The offer is concrete and supported by `SetNewsletterDefaults`: 15%, one use, no minimum spend, expiry date. Keep the code on its own line and the real expiry date. Do not add urgency beyond that date.

Recommended subject:

> Your 15% welcome code for Eden Flowers

It states the offer without the inbox filler “inside.” Keep the short thank-you and offer paragraph. After the expiry line, add:

> Shop flowers:
> {store_url}

Use the store route. This needs a new template assign; the existing welcome template receives only the code and expiry. Do not imply the discount repeats on future subscription orders.

**Variant checked:** welcome code. Current Finnish “Käytä se kassalla” can be made more explicit as “Käytä koodi kassalla.”

## 12. Newsletter already subscribed

**Verdict: make the acknowledgment friendlier and add a shop link.** The existing “so there's no need to sign up again” sounds corrective. The customer mainly wants the code.

Recommended opening:

> You're already subscribed to the Eden Flowers newsletter. Here's your 15% welcome code again:
> {code}
>
> Use it at checkout by {date}.
>
> Shop flowers:
> {store_url}

Keep the subject. The worker checks that the code is unused and unexpired before sending this version, so “Use it” is supported. Preserve the same code and expiry; do not frame this as a new offer.

**Variant checked:** existing usable code. Apply the less corrective opening in Swedish and Finnish too.

## 13. Newsletter resubscribed

**Verdict: correct the assumed history.** The worker sends this email whenever an existing promotion is used or expired. It does not establish that the customer unsubscribed and returned. “Welcome back” can therefore be inaccurate.

Recommended subject:

> Your Eden Flowers newsletter subscription

Recommended body:

> Hi,
>
> You're subscribed to the Eden Flowers newsletter.
>
> Browse the flowers in the shop:
> {store_url}
>
> Warm wishes,
>
> Eden Flowers

Use `/store`, rather than the current homepage URL. “Browse the flowers” avoids claiming that the whole range is seasonal. Keep “Welcome back” only if the send path supplies evidence of a prior unsubscribe followed by a new subscription.

**Variant checked:** resubscription preview. Add separate used-code and expired-code scenarios, even if they intentionally share wording.

## 14. Sign-in code

**Verdict: keep.** The code is first in the subject, isolated in the body, and clearly described as a sign-in code. The expiry and unsolicited-request instruction answer the relevant questions. The brand-only signature is appropriate here.

Do not add promotional content or a shopping CTA. The only task is signing in. The ten-minute claim is supported by the installed AshAuthentication OTP strategy's default `otp_lifetime: {10, :minutes}`; the user resource does not override it.

**Variant checked:** sign-in code. The Swedish and Finnish versions preserve the same simple structure.

## 15. Email-change code

**Verdict: shorten and clarify the purpose.** The current subject is long, especially in Finnish. The body phrase “confirm this as the email” is awkward.

Recommended subject:

> {code} is your email change code for Eden Flowers

Recommended body opening:

> Enter this code in your account to confirm your new email address:

Keep the code, expiry and ignore-if-unrequested sentence. The account implementation uses a ten-minute expiry, which supports that claim. Preserve the distinction from the sign-in email in all languages.

**Variant checked:** email-change code.

## Review-data issues and remaining evidence

These affect how confidently the previews can be approved:

- The sample cancellation deadline is 12 November for fulfillment on 14 November. The actual calculation subtracts five days, giving 9 November. Correct the fixture, not the customer-facing rule.
- Several pickup examples remove the €10 fee but retain a €64 total for €54 of items. Correct totals and balances together.
- Preview order confirmations inherit an unpaid balance from the shared fixture despite representing a paid receipt. Use coherent payment states even where the body does not currently display them.
- Preview product/course names and wedding selections remain English in all languages. These are fictional data, not necessarily missing template translations. Use localized fixtures to review complete customer messages.
- The exports use localhost account/store URLs and a fictional Stripe payment URL. Production senders use the application's payment-link builder; exported links are not a production link check.
- Receipt PDFs are attached by senders, outside the preview builders. The delivery-photo preview uses fictional bytes. Review attachment appearance separately.
- Missing wording scenarios include settled/overpaid order details, pickup cancellation, partially paid course bookings and independently present subscription discount/card message.
- Sign-in and email-change code lifetimes were checked locally. Current refund arrival guidance still needs provider evidence.

## Implementation order

1. Fix failed-payment behavior wording, the newsletter return assumption, Finnish pickup cancellation wording and course cancellation branches.
2. Add newsletter shop links and make payment amounts precede payment CTAs.
3. Apply the short editorial changes; keep fulfillment and sign-in emails substantially as they are.
4. Update all three languages and preview fixtures together, then regenerate the review exports.

No production email templates were changed in this review.
