# Ubiquitous Language

## People

| Term         | Definition                                                                                  | Aliases to avoid               |
| ------------ | ------------------------------------------------------------------------------------------- | ------------------------------ |
| **Customer** | A person who places an Order; identified by their email and (when known) name               | Client, buyer, shopper         |
| **User**     | An authentication identity (`Edenflowers.Accounts.User`) that a returning Customer signs in as | Account holder, login          |
| **Recipient**| The person an Order is delivered or picked up for; may or may not be the Customer themselves | Receiver, addressee            |
| **Florist**  | The shop operator (Jennie) who arranges flowers and fulfils Orders                          | Shop, vendor, staff            |

## Order lifecycle

| Term                   | Definition                                                                                       | Aliases to avoid                       |
| ---------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------- |
| **Order**              | A Customer's purchase request, identified by an Order reference (e.g. `EF-1847`)                 | Purchase, transaction, cart            |
| **Checkout state**     | Where an Order sits in the pre-purchase flow: `:contact_details`, `:gift_options`, `:delivery`, `:payment` — collapses to `:placed` once finalized | "Status", "step"                       |
| **Placed Order**       | An Order whose Checkout state has reached `:placed` — i.e. paid and committed                    | Completed order, confirmed order       |
| **Payment status**     | The financial state of a Placed Order: `:pending`, `:paid`, `:failed`, `:refunded`               | "Order status" (overloaded)            |
| **Fulfillment status** | The physical-delivery state of a Placed Order: `:pending` or `:fulfilled` (binary, no middle)    | "Order status" (overloaded), "stage"   |
| **Open Order**         | A Placed Order with Fulfillment status `:pending` — the Customer is still waiting to receive it  | Active order, in-flight, pending order |
| **Past Order**         | A Placed Order with Fulfillment status `:fulfilled` — already delivered or picked up             | Historical order, completed, delivered |

## Fulfillment

| Term                   | Definition                                                                                  | Aliases to avoid                  |
| ---------------------- | ------------------------------------------------------------------------------------------- | --------------------------------- |
| **Fulfillment method** | How an Order reaches its Recipient: `:delivery` (home delivery) or `:pickup` (in-store)     | Shipping, "method"                |
| **Fulfillment date**   | The calendar date the Customer chose for delivery or pickup; no time component is stored    | Delivery date, pickup date        |
| **Delivery instructions** | Free-text notes attached to a delivery Order (e.g. "Door code 2143")                     | Notes for courier, delivery notes |
| **Card message**       | The handwritten note included on a gift Order's accompanying card                           | Gift message, note                |
| **Gift Order**         | An Order with `gift: true`; the Recipient differs from the Customer and a Card message may be present | Gifted order                      |

## Account page concepts (this PR)

| Term              | Definition                                                                                | Aliases to avoid             |
| ----------------- | ----------------------------------------------------------------------------------------- | ---------------------------- |
| **Account page**  | The signed-in Customer's view at `/account`, split into Open Orders and Past Orders sections | "Profile", "dashboard"     |
| **Display title** | The human-readable name of an Order, derived from its first non-card Line Item's `product_name`, with `+ N more` suffix when multiple items exist | "Order name"                 |
| **Self-recipient**| An Order where `gift: false`, treated in copy as "for yourself" rather than naming the Recipient | "Self order"                 |

## Relationships

- A **Customer** has a corresponding **User** once they've authenticated; guest checkout creates an Order without a User.
- An **Order** belongs to at most one **User**; an unauthenticated guest Order has no User.
- A **Placed Order** has exactly one **Payment status** and exactly one **Fulfillment status**, evolving independently.
- An **Open Order** becomes a **Past Order** when its **Fulfillment status** flips from `:pending` to `:fulfilled` — there is no intermediate stored state.
- A **Gift Order** has a distinct **Recipient** from the **Customer**; a non-gift Order's Recipient is the **Customer** themselves (the "self-recipient" case).
- A **Fulfillment method** of `:pickup` means the **Recipient** collects at the Florist's shop; `:delivery` means a courier brings the Order to the Recipient's address.

## Example dialogue

> **Dev:** "On the Account page, an Open Order shows 'Arriving Friday 15 May' — is that the Fulfillment date or something derived?"

> **Domain expert:** "That's just the Fulfillment date the Customer picked at checkout. We don't store a time window, so we render only the date with a method-specific verb — 'Arriving' for delivery, 'Ready for pickup' for pickup."

> **Dev:** "Got it. And when the Fulfillment status flips to `:fulfilled`, the Order moves from the Open Orders section to the Past Orders section?"

> **Domain expert:** "Right. Same Placed Order — same row in the database — it just satisfies a different filter. The Customer didn't 'do' anything; the Florist marked it fulfilled."

> **Dev:** "If a Gift Order is fulfilled, the Past row should say 'to Anna' — but a self-recipient Order should say 'for yourself'?"

> **Domain expert:** "Yes. The signal is the `gift` flag, not name comparison. A non-gift Order is by definition for the Customer themselves, regardless of what `recipient_name` happens to contain."

## Flagged ambiguities

- **"Status"** was used loosely to mean Checkout state, Payment status, or Fulfillment status. Always qualify which one — e.g. "Fulfillment status: pending" rather than "the order is pending".
- **"Stage"** appeared in the wireframe data (`stage: "out_for_delivery"`) to collapse Fulfillment status, Payment status, and Checkout state into a single field. In production code this is fictional — there is no `stage` attribute. Use the specific status name instead.
- **"Completed"** is ambiguous: `Order.get_all_completed/0` historically returned all **Placed Orders** regardless of Fulfillment status, but the word suggests they're finished (i.e. fulfilled). Replacing with `:open_orders` and `:past_orders` removes the overload.
- **"Account"** can mean the Account page, the **User** auth identity, or — colloquially — the **Customer**. Prefer the specific term: "the signed-in Customer", "the User record", "the Account page".
- **"Order details"** was used both for (a) the still-stub `/order/:id` page and (b) the rich meta inside an Open Order card. Reserve "Order detail page" for the route; use "Open Order card" or "Past Order row" for the Account page surfaces.
