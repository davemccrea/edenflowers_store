# Eden Flowers

The storefront and back office for a single-florist flower shop in Vaasa: customers buy arrangements for delivery or pickup, and Jennie fulfils them.

## Language

### Orders

**Placed**:
An order the shop has committed to make. An Online Order is placed when its payment succeeds; a Custom Order is placed when Jennie saves it, and may still be awaiting payment.
_Avoid_: Confirmed, submitted

**Cancelled**:
A placed order Jennie has decided will not be made. Cancelling never refunds; refunds are handled separately in Stripe.
_Avoid_: Void, deleted, abandoned (an abandoned order is a cart that was never placed)

**Online Order**:
An order a customer places themselves through checkout.
_Avoid_: Web order, cart order

**Custom Order**:
An order Jennie enters in the admin on a customer's behalf, however the request reached her (phone, in the shop, email, message). It may contain catalogue items, items she describes and prices herself, or both.
_Avoid_: Phone order, manual order, bespoke order

**Florist Note**:
Jennie's private working note on any order — what was agreed, constraints like "deliver by 10:30, service at 11:00". Never shown to the Customer or Recipient.
_Avoid_: Comment, internal note, order notes (and distinct from the Card Message and Delivery Instructions, which come from the Customer)

### Subscriptions

**Subscription**:
A customer's standing request for a florist's-choice bouquet every one, two or four weeks, delivered to the same Recipient. It is not an order: it creates orders, and holds only the schedule, the delivery details and the saved card. Set up by paying for the first order at checkout.
_Avoid_: Plan, membership, recurring order

**Occurrence**:
One order a Subscription creates: an ordinary placed Online Order, charged to the saved card, that Jennie makes like any other.
_Avoid_: Renewal, instalment, delivery (a delivery is how any order reaches its Recipient)

### Payment

**Payment Link**:
A private link Jennie gives a customer so they can pay what an order still owes online: a custom order not yet paid, or a balance left by an edit. It never expires, and asks for nothing once the balance is settled or the order is cancelled.
_Avoid_: Invoice, payment request, Stripe link

**In-person Payment**:
A payment Jennie takes outside the website — on the Zettle card reader, by MobilePay, in cash, or by a Zervant invoice paid to her bank — and then records against the order.
_Avoid_: Offline payment, manual payment, till payment

**Payment**:
Money that moved for an order: through Stripe, or taken in person. A refund is a negative Payment. An order can have several.
_Avoid_: Transaction, charge

**Balance**:
What is still owed on a placed order: its total minus what has been paid. Positive is to collect, negative is to refund; editing a paid order is what usually leaves one.
_Avoid_: Amount mismatch, outstanding, difference

### People

**Customer**:
The person who places and pays for an order. Reachable by email, phone, or both.
_Avoid_: Buyer, sender, client

**Recipient**:
The person the flowers are for. Often not the Customer; for a funeral it is effectively the church or chapel receiving the delivery.
_Avoid_: Receiver, giftee
