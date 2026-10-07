# Enable Stripe webhook events in the dashboard

Status: ready-for-human

In the Stripe dashboard, add an endpoint at `https://<domain>/webhook/stripe` subscribed to:

- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `payment_intent.canceled`
- `setup_intent.succeeded` (saves a subscription's replacement card if the customer never returns from Stripe)
- `refund.created`
- `refund.updated`

Set the endpoint's signing secret (`whsec_…`) as the `:stripe_webhook_secret` config. Handlers live in `lib/edenflowers_web/webhooks/stripe_handler.ex`.
