# Eden Flowers — Ship Plan

Blockers are content stubs and one prod-email gap. Engineering work is small.

---

## P0 — Must do before launch

### 1. Configure production email adapter

`config/config.exs:89` sets `Swoosh.Adapters.Local`; `runtime.exs:160-176` only has a commented-out Mailgun example. With no prod adapter, OTP sign-in codes and receipts silently fail to send. OTP is the only sign-in path.

**Fix:** wire a provider (SES / Resend / Postmark / Mailgun) in `runtime.exs`, set API key env vars, verify sender domain (SPF/DKIM/DMARC). ~30 min.

### 2. Account page renders nothing

`lib/edenflowers_web/live/account_live.ex:18` — `mount/3` loads `orders` but the template body is empty.

**Fix:** render `@orders` (reference, date, status, total, link to `OrderLive`). Reuse `OrderLive` helpers / `Edenflowers.Localize.Format`. ~30 min.

### 3. Contact page is title-only

`lib/edenflowers_web/live/contact_live.ex:14` — only `<h1>Contact</h1>`.

**Fix:** static info (email, phone, address, hours). Skip the form unless spam protection is wired. ~20 min.

### 4. About page has Lorem ipsum

`lib/edenflowers_web/live/about_live.ex:54-57` and `:80-83` — placeholder Latin in Jennie's bio.

**Fix:** drop in real copy. Blocked on Jennie, not engineering. ~10 min.

### 5. Weddings & Condolences pages are skeletons

`weddings_live.ex`, `condolences_live.ex` — only render `<h1>`. Both linked from nav (`layouts.ex:162-163`).

**Decision:** either fill with a paragraph + "Contact us" CTA, or remove from nav and delete the routes until post-launch. Empty pages look worse than no page. ~10 min either way.

### 6. Courses page lists nothing

`lib/edenflowers_web/live/courses_live.ex:7-8` — loads `upcoming_courses` but never renders. Linked from nav (`layouts.ex:161`).

**Decision:** same as #5. ~20 min if rendering, ~10 if removing.

### 7. Legal pages (Privacy / Terms)

No routes exist. GDPR + Stripe usually require at minimum a Privacy Policy linked in the footer.

**Fix:** minimal static HEEx pages. Copy from a generator + Jennie's review. ~30 min.

---

## P1 — Should do before launch

### 8. Verify Stripe webhook secret in prod

Order finalization + receipt email both depend on `payment_intent.succeeded` (`endpoint.ex:53-56`). Missing/stale `STRIPE_WEBHOOK_SECRET` = payments succeed but orders never finalize and customers never get receipts.

**Fix:** confirm env var in phoenix-ansible deploy config; confirm Stripe dashboard shows prod endpoint healthy. ~10 min.

### 9. Smoke-test end-to-end in staging

OTP sign-in → browse → cart → Stripe test card → webhook fires → receipt email with PDF arrives → order shows in `/admin` and `/account`. Catches #1 and #8.

**Fix:** ~30 min.

### 10. Maintenance mode kill-switch

`MAINTENANCE_MODE` + `MAINTENANCE_BYPASS_SECRET` are wired (`runtime.exs:52-56`, `plugs/maintenance.ex`). Verify on the prod server before you need it.

**Fix:** ~5 min sanity check.

---

## P2 — Defer if tight

### 11. `here_api.ex:15` stray TODO

No-context `# TODO` above `@lang "sv"`. Resolve or delete. 2 min, cosmetic.

### 12. `endpoint.ex:11` session max_age commented out

Sessions end on browser close. Uncomment with a deliberate value if you want persistent login.

### 13. Receipt-plan deferred items

`docs/receipt-integration-plan.md` lists mixed VAT rates and shop-identity duplication as deferred. Not shipping-blockers.

---

## Post-launch backlog

- Inventory / stock depletion
- Refund flow from admin
- Order fulfillment status updates to customer (milestone emails)
- Shipping label / carrier integration
- Admin analytics / reporting
