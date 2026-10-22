# Eden Flowers

The storefront and back office for a single-florist flower shop in Vaasa: customers buy arrangements for delivery or pickup, and Jennie fulfils them.

## Language

### Orders

**Placed**:
An order the shop has committed to make. An Online Order is placed when its payment succeeds; a Custom Order is placed when Jennie saves it, and may still be awaiting payment.
_Avoid_: Confirmed, submitted

**Cancelled**:
A placed order that will not be made. When Jennie cancels, nothing is refunded; she refunds separately in Stripe. A Customer can cancel their own Online Order from their account until 5 days before its fulfillment date, which refunds everything they paid by card; orders closer than that, or paid outside Stripe, go through Jennie.
_Avoid_: Void, deleted, abandoned (an abandoned order is a cart that was never placed)

**Online Order**:
An order a customer places themselves through checkout.
_Avoid_: Web order, cart order

**Custom Order**:
An order Jennie enters in the admin on a customer's behalf, however the request reached her (phone, in the shop, email, message). It may contain catalogue items, items she describes and prices herself, or both. A sale over the counter is a Custom Order too: every sale the shop makes is an order, so the orders are the shop's complete record of its sales.
_Avoid_: Phone order, manual order, bespoke order, walk-in sale, till sale

**Florist Note**:
Jennie's private working note on any order — what was agreed, constraints like "deliver by 10:30, service at 11:00". Never shown to the Customer or Recipient.
_Avoid_: Comment, internal note, order notes (and distinct from the Card Message and Delivery Instructions, which come from the Customer)

### Catalogue

**Add-on**:
A product from an add-on category, like a card or chocolate, that goes with flowers but is never sold on its own: a cart of only add-ons can't be checked out, as a delivery for one alone would cost more than it earns. Custom Orders aren't held to this.
_Avoid_: Extra, upsell, accessory

**Stock**:
How many of a size are on the shelf and not yet promised to a placed order. Only some sizes have stock, like a batch of wreaths or bought-in chocolates; the rest are made to order and never run out. A placed order takes its stock, and cancelling puts it back. Subscriptions never take stock, as their bouquets are made fresh.
_Avoid_: Inventory, quantity on hand

### Subscriptions

**Subscription**:
A customer's standing request for a subscribable product every one, two or four weeks, for the same Recipient, delivered or picked up. It is not an order: it creates orders, and holds only the schedule, the delivery details and the saved card. The customer opts in on a subscribable product's page, choosing how often for that cart line, and sets it up by paying for the first order at checkout. The same product bought once is an ordinary order.
_Avoid_: Plan, membership, recurring order

**Occurrence**:
One order a Subscription creates: an ordinary placed Online Order, charged to the saved card, that Jennie makes like any other.
_Avoid_: Renewal, instalment, delivery (a delivery is how any order reaches its Recipient)

### Payment

**Payment Link**:
A private link Jennie gives a customer so they can pay what an order still owes online: a custom order not yet paid, or a balance left by an edit. It never expires, and asks for nothing once the balance is settled or the order is cancelled.
_Avoid_: Invoice, payment request, Stripe link

**Payment**:
Money that moved for an order or a course booking, by any method: Stripe, the Zettle card reader, MobilePay to Jennie's own number, cash, or a Zervant invoice paid to her bank. Stripe payments are recorded from Stripe; Jennie records every other method herself, wherever it was paid. A refund is a negative Payment, made the same way the money came in. An order or booking can have several.
_Avoid_: Transaction, charge, in-person payment, offline payment, manual payment

**Balance**:
What is still owed on a placed order or a confirmed course booking: its Total due minus what has been paid, leaving out Goodwill refunds. Positive is to collect, negative is to refund; editing a paid order or cancelling one is what usually leaves one. Once the Total due drops below what was paid, only money still held above it is owed back.
_Avoid_: Amount mismatch, outstanding, difference

**Total due**:
What a placed order or confirmed course booking is still to be paid for, before what's been paid is taken off. Zero once cancelled, apart from what a booking keeps when Jennie hands back less than was paid. The order's or booking's total itself stays as ordered, for the receipt.
_Avoid_: Amount due, outstanding

**Settled**:
Nothing is owed either way, or everything taken was handed back.

**Goodwill refund**:
Money handed back to an unhappy customer without lowering what was sold, on a placed order or a confirmed course booking with nothing left to collect, up to what's still held. It leaves the Balance where it was, so the order or booking stays settled, and one of everything received reads as refunded. A Stripe refund made in the dashboard beyond what was owed back is one too. Jennie can note why. The monthly report still shows it as a negative row.
_Avoid_: Discount, compensation, credit

**Undo** (a payment):
Taking back a payment or refund Jennie recorded by mistake, by recording the opposite amount against it. Once per payment, never a Stripe one. Not a refund: an undone payment never counted as money taken.
_Avoid_: Void, reversal, correction

### People

**Customer**:
The person who places and pays for an order. Reachable by email, phone, or both.
_Avoid_: Buyer, sender, client

**Recipient**:
The person the flowers are for. Often not the Customer; for a funeral it is effectively the church or chapel receiving the delivery.
_Avoid_: Receiver, giftee
