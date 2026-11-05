# Eden Flowers

The storefront and back office for a single-florist flower shop in Vaasa: customers buy arrangements for delivery or pickup, and Jennie fulfils them.

## Language

### Orders

**Placed**:
An order the shop has committed to make. An Online Order is placed when its payment succeeds; a Custom Order is placed when Jennie saves it, and may still be awaiting payment.
_Avoid_: Confirmed, submitted

**Cancelled**:
A placed order, or a confirmed course booking, that will not go ahead. When Jennie cancels, she chooses how much to keep as a cancellation charge, from nothing up to its Total due, whether or not anything was paid, and refunds what was paid above it: card payments go back through Stripe at once, and money paid in person is left as a Balance for her to hand back. Any of the charge not yet paid is left as a Balance to collect, to settle with the customer; cancelling never creates an invoice. A course booking's charge starts at its course's cancellation terms, an order's at nothing. The customer is emailed unless she unticks it, as she rewrites the email if she likes; her reason for cancelling is for her own record. Customers cancel a course booking by asking Jennie. A Customer can cancel their own Online Order from their account until 3 days before its fulfillment date (the Change deadline), which refunds everything they paid by card; orders closer than that, or paid outside Stripe, go through Jennie.
_Avoid_: Void, deleted, abandoned (an abandoned order is a cart that was never placed)

**Course booking**:
A place, or group of places, the shop has committed to provide: confirmed when Jennie accepts a manual booking, or when website checkout is paid. It holds places even while money is owed; customers change or cancel a confirmed booking only by asking Jennie.
_Avoid_: Hold, reservation, pending booking

**Manual course booking**:
A Course booking Jennie accepts on a customer's behalf, however the request reached her, including after online booking closes or when the course is full. Like a Custom Order, it can be paid through a Payment Link or in person at the course. Confirmation of places does not mean payment was received.
_Avoid_: Invite, awaiting payment booking

**Course checkout**:
An unfinished website purchase that holds no places and is not yet a Course booking. The customer may revise the same checkout until payment confirms its current details, with any price difference left as a Balance.
_Avoid_: Hold, reservation, pending booking

**Online Order**:
An order a customer places themselves through checkout.
_Avoid_: Web order, cart order

**Custom Order**:
An order Jennie enters in the admin on a customer's behalf, however the request reached her (phone, in the shop, email, message). It may contain catalogue items, items she describes and prices herself, or both. A sale over the counter is a Custom Order too; occasional weddings and bespoke work can instead be billed through a standalone Invoice.
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

**Charge day**:
2 days before an Occurrence's delivery or pickup: the day its order is created and the saved card charged. It falls after the Change deadline, so a customer can't cancel an Occurrence from their account.
_Avoid_: Billing day, renewal date

**Change deadline**:
3 days before an Occurrence's delivery or pickup (Tuesday for a Friday): the last day the customer can pause, change or cancel it from their account. An Online Order shares it as the last day its customer can cancel it themselves.
_Avoid_: Cutoff, lock date

### Payment

**Payment Link**:
A private link Jennie explicitly gives a customer so they can pay what a placed order or confirmed Course booking still owes online. It does not expire with time, and asks for nothing once the Balance is settled or the purchase is cancelled; paying a booking's link does not book its places again.
_Avoid_: Invoice, payment request, Stripe link

**Payment received**:
The email telling a customer their payment for an order or booking arrived outside checkout: through a Payment Link, or recorded by Jennie. It carries the receipt and never asks for more money, even if some is still owed.
_Avoid_: Receipt email (the order receipt is what online checkout sends), payment confirmation

**Payment reminder**:
The email Jennie sends by hand to ask for a Balance still owed on an order or booking, with its Payment Link. Never sent automatically.
_Avoid_: Bill, dunning, payment request

**Payment**:
Money that moved for exactly one order, Course booking or Invoice; a refund or Undo is a negative Payment. Orders and bookings accept their usual payment methods, while Invoice Payments are bank transfers recorded by Jennie and affect only that Invoice, even one for an order: each euro is counted where it arrived.
_Avoid_: Transaction, charge, in-person payment, offline payment, manual payment

**Invoice**:
A bill owning its buyer details, billed lines and VAT, for weddings, bespoke work and private courses, or for one Custom Order on invoice terms with nothing paid. A draft is editable and unnumbered; issuing freezes the document and assigns its number, and only its own bank-transfer Payments settle it. Issued and not credited, an Invoice for an order covers that much of the order's Balance and, until it is credited, the order can't be cancelled or edited in a way that changes its amount per VAT rate, date or terms.
_Avoid_: Bill, Zervant invoice, payment request (a Payment Link is not an Invoice)

**Credit note**:
A numbered document that fully reverses one unpaid issued Invoice, including its original VAT, while preserving the original document. Paid or partly paid corrections go to the accountant; a Credit note is never a cash refund.
_Avoid_: Credit invoice, refund (a Refund is money handed back)

**Business customer**:
A company billed on a standalone Invoice with its name, Y-tunnus and billing address, plus an optional reference of its own (viitteenne).
_Avoid_: Corporate customer, B2B customer, company account

**Balance**:
What is still to collect on a placed order or a confirmed course booking itself: its Total due minus what its issued, uncredited Invoices bill and what has been paid, leaving out Goodwill refunds. An invoiced order reads 0 before its Invoice is paid; Balance means left to collect here, not paid. Positive is to collect, negative is to refund; editing a paid order or cancelling one is what usually leaves one. Once the Total due drops below what was paid, only money still held above it is owed back.
_Avoid_: Amount mismatch, outstanding, difference

**Total due**:
What a placed order or confirmed course booking is still to be paid for, before what's been paid is taken off. Once cancelled, the cancellation charge, paid or not. The order's or booking's total itself stays as ordered, for the receipt.
_Avoid_: Amount due, outstanding

**Settled**:
Nothing is owed either way according to the money recorded now, or everything taken was handed back. This is not a promise that no payment is still processing or could arrive later.

**Refund**:
Money Jennie hands back on a placed order or confirmed course booking, cancelled or not, once nothing is left to collect, up to what's still held: by card through Stripe, or by recording money she handed back herself. The customer is emailed unless she unticks it, as she rewrites the email if she likes; her note on the refund is for her own record. What was owed back is an ordinary refund; any more is a Goodwill refund.
_Avoid_: Credit, reimbursement

**Goodwill refund**:
The part of a Refund beyond what was owed back, as when a customer wasn't happy. It leaves the Balance where it was, so the order or booking stays settled, and one of everything received reads as refunded. A Stripe refund made in the dashboard beyond what was owed back is one too. Jennie never chooses it: the admin just says Refund. The monthly report still shows it as a negative row.
_Avoid_: Discount, compensation, credit

**Undo** (a payment):
Taking back a payment or refund Jennie recorded by mistake, by recording the opposite amount against it. Once per payment, never a Stripe one or a Gift voucher one. Not a refund: an undone payment never counted as money taken.
_Avoid_: Void, reversal, correction

**Gift voucher**:
Money paid in advance, valid a year, that whoever holds its code spends on flowers, subscriptions and courses. It pays like money, not like a discount: each use is a Payment from it, and what it paid for being cancelled or refunded puts that money back on it, never into cash. What's left is its amount less those Payments. At checkout it only lowers what the card is asked for; it pays when the order is placed or the booking confirmed. Presentkort in Swedish, lahjakortti in Finnish.
_Avoid_: Gift card (the greeting card in checkout's card slot), Promotion, promo code, credit

### People

**Customer**:
The person who places and pays for an order. Reachable by email, phone, or both.
_Avoid_: Buyer, sender, client

**Recipient**:
The person the flowers are for. Often not the Customer; for a funeral it is effectively the church or chapel receiving the delivery.
_Avoid_: Receiver, giftee

**Reviewer**:
Someone invited to check the site before it goes out, by a `reviewer` flag set in the database. Admins count as Reviewers too. They have no back office access.
_Avoid_: Tester, QA

### Review

**Review note**:
A Reviewer's comment on one element of a page, left with Option+Click and stored with the element's context. Open until resolved; there is no admin page for them. `just feedback` lists the open ones and `just resolve-feedback` resolves them.
_Avoid_: Review on its own (it could mean a customer's product review)
