# Summary

## Architecture

- Domain logic lives in Ash domains split by concern—Accounts, Store, and a new Services domain for workshops—each exposing resources via code_interface helpers (lib/edenflowers/accounts.ex:1, lib/edenflowers/store.ex:1, lib/edenflowers/services.ex:1).
- Checkout is modeled as an Ash resource with multi-step state, derived totals, Stripe payment metadata, and custom changes for promotion lookup and fulfillment processing (lib/edenflowers/store/order.ex:67, lib/edenflowers/store/order.ex:286, lib/edenflowers/store/order.ex:362).
- Cart items publish over Phoenix PubSub so LiveViews can stay in sync; mounts wire in hooks that subscribe and refresh the order or reset empty carts (lib/edenflowers/store/line_item.ex:50, lib/edenflowers_web/hooks/handle_line_item_changed.ex:1, lib/edenflowers_web/plugs/init_store.ex:1).
- Delivery pricing and eligibility rely on dedicated service modules: Fulfillments encapsulates pricing/date rules while HereAPI wraps external geocoding/distance calls (lib/edenflowers/fulfillments.ex:1, lib/edenflowers/here_api.ex:1).
- Authentication is handled through AshAuthentication with magic-link strategy and token storage policies, plus LiveView helpers for route protection (lib/edenflowers/accounts/user.ex:9, lib/edenflowers_web/live_user_auth.ex:1).
- The Phoenix endpoint runs on Bandit, localizes via CLDR plugs, exposes Stripe webhooks that trigger Oban jobs for email notifications, and serves LiveView-first pages (lib/edenflowers_web/router.ex:17, lib/edenflowers_web/endpoint.ex:52, lib/edenflowers_web/stripe_handler.ex:6, lib/edenflowers/workers/send_order_confirmation_email.ex:1).

## Design Notes

- Store catalog resources use Ash aggregates/calculations to surface pricing, inventory, and promotion effects without extra SQL, e.g., product variants sorted by price and line-item totals with tax/discount math (lib/edenflowers/store/product_variant.ex:34, lib/edenflowers/store/line_item.ex:79).
- Fulfillment options support translated fields and validation rules that tie deadlines to same-day delivery settings (lib/edenflowers/store/fulfillment_option.ex:21, lib/edenflowers/store/fulfillment_option.ex:32).
- Live UI leans on shared layout components and gettext, with per-view data loaded from Ash code interfaces (lib/edenflowers_web/live/courses_live.ex:6, lib/edenflowers_web/live/checkout_live.ex:25).
- Background workflows favor declarative Oban workers; email sending is stubbed but isolated for future templating (lib/edenflowers/workers/send_order_confirmation_email.ex:10).

## Current Status

- The repo is ahead of origin with untracked work introducing the Services domain for courses and registrations, including config wiring and Ash resource snapshots (config/config.exs:63, lib/edenflowers/services/course.ex:11, priv/resource_snapshots/repo/courses/).
- Course registration schema has a registered timestamp column but the resource omits that attribute, so data written via Ash would drop the value—needs alignment (priv/repo/migrations/20250626102934_courses_and_registrations.exs:28, lib/edenflowers/services/course_registrations.ex:29).
- CoursesLive lists upcoming workshops and shows a “Register Now” button, yet there is no event handler or form hooking into CourseRegistration.register_for_course/1—signup flow is incomplete (lib/edenflowers_web/live/courses_live.ex:137, lib/edenflowers/services/course_registrations.ex:11).
- No tests cover the new Services resources or UI; existing suite still targets the store domain (test/fulfillments_test.exs:1, test/order_test.exs:1).
- Miscellaneous TODOs remain around locale handling, checkout completion verification, translated fulfillment names, and production URLs, signaling planned refinement (lib/edenflowers_web/router.ex:79, lib/edenflowers_web/controllers/checkout_complete_controller.ex:7, lib/edenflowers/store/fulfillment_option.ex:21, lib/edenflowers_web/live/ checkout_live.ex:230).