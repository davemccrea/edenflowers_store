# One customer email per job, in Jennie's voice

Each customer email does one job and says what happened before anything else. When a different thing happens, that's a different email, even if most of the wording is the same: Order details and Order updated are two emails, not one with a switch. A detail that varies within the same news (a name, pickup or delivery, a gift recipient, seats, how it was paid, an optional note) stays a variable in one email. Duplicated wording between emails is fine: each is proofread in three languages on its own.

Emails are in Jennie's voice and signed by her, unless they only confirm something routine the customer did themselves or are a routine notice. Those are matter-of-fact, signed "Eden Flowers" and sent from the automated address: the customer's own cancellation, Subscription delivery charged, the subscription heads-up, Already subscribed, and sign-in and email-change codes. An automatic email in Jennie's voice never pretends she did something by hand.

Every email that one of Jennie's actions sends has a tick box and a message box beside it, and a live preview of what the customer will get. Her message goes after the line saying what happened and before the details, and the order log keeps it with the email it went in. A cancellation reason and a refund note are that message, not fields of their own.

Jennie's inbox receives only shop notices. Every customer email is copied to info+copy@, which Fastmail files out of her inbox, including the ones a customer's own action sends. When she needs to act on what a customer did, she gets a shop notice.

ADR 0005 still says how each email is queued and sent once.

## Considered Options

- **One email per kind of record, versioned by state** (order details as details, card refused or bill). Rejected: the versions said different things, each switch had to be read in three languages at once, and a late first send of the details read like a reminder to pay.
- **The voice follows strictly who acted**: Jennie's voice only for her own actions, the shop's for everything automatic. Rejected: most automatic emails (a receipt, a booking confirmation) are a customer's first contact with her, and read better in her voice. Only routine confirmations need to sound like a system.

## Consequences

- A new kind of news is a new email with its own builder, template and scenarios on the admin Emails page.
- Every action that emails a customer for Jennie takes a message argument as well as `email_customer?`.
- A booking confirmation is one email whether or not it's paid: the news is that places are booked. A Balance still owed is a detail of it, and a receipt is attached only for money actually received. A later payment is different news, so it gets Payment received.
