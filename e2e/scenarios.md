# E2E Test Scenarios (Playwright)

Full browser tests covering the customer journey from store to confirmation email.
Stripe is exercised via test mode with real test cards. Here API is stubbed at
the server level (returns a fixed coordinate + distance for any input address).

---

## Scenario 1 — Guest pickup order

1. Visit the store, open a product page
2. Select a variant, add to cart
3. Enter name and email (step 1)
4. Skip gift options (step 2)
5. Select pickup, choose a date (step 3)
6. Enter Stripe test card `4242 4242 4242 4242`, submit (step 4)
7. Assert: order confirmation page is shown with correct total
8. Assert: confirmation email is received at the address entered in step 3

---

## Scenario 2 — Gift order with promo code

1. Visit the store, open a product page
2. Select a variant, add to cart
3. Apply a promo code — assert the discounted total is displayed
4. Enter name and email (step 1)
5. Enable gift, enter recipient name and message (step 2)
6. Select pickup, choose a date (step 3)
7. Pay with test card
8. Assert: confirmation page shows discounted price and recipient details
9. Assert: confirmation email reflects the discount and gift message

---

## Scenario 3 — Delivery order

1. Visit the store, open a product page
2. Select a variant, add to cart
3. Enter name and email (step 1)
4. Skip gift options (step 2)
5. Select delivery, enter an address, choose a date (step 3)
   - Here API stub returns a distance within the free delivery threshold
6. Pay with test card
7. Assert: confirmation page shows the delivery address and correct fulfillment cost

---

## Scenario 4 — Failed payment, then retry

1. Visit the store, add a product to cart, complete steps 1–3
2. Enter Stripe decline card `4000 0000 0000 0002`
3. Assert: payment error is shown, order is not finalised
4. Re-enter with success card `4242 4242 4242 4242`
5. Assert: order confirmation page is shown

---

## Infrastructure notes

- **Stripe**: use test mode API keys; interact with Stripe Elements directly in the browser
- **Here API**: stub responses at the server level via a test configuration flag;
  no network calls to Here during E2E runs
- **Email**: capture via [MailHog](https://github.com/mailhog/MailHog) or
  [Mailpit](https://github.com/axllent/mailpit) running alongside the test server;
  assert on subject, recipient, and key content
- **Test data**: seed via the existing `Generator` helpers called from a
  Playwright `globalSetup` script (hitting the app's internal setup endpoint or
  running `mix` directly before the suite)
