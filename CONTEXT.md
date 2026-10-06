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

### Payment

**Payment Link**:
A private link Jennie gives a customer so they can pay a placed, unpaid order online. It never expires, and stops working once the order is paid or cancelled.
_Avoid_: Invoice, payment request, Stripe link

**In-person Payment**:
A payment Jennie takes outside the website — on the Zettle card reader, by MobilePay, or in cash — and then records against the order.
_Avoid_: Offline payment, manual payment, till payment

### People

**Customer**:
The person who places and pays for an order. Reachable by email, phone, or both.
_Avoid_: Buyer, sender, client

**Recipient**:
The person the flowers are for. Often not the Customer; for a funeral it is effectively the church or chapel receiving the delivery.
_Avoid_: Receiver, giftee
