---
target: session subscription UI changes
total_score: 20
max_score: 32
na_heuristics: 7,10
p0_count: 0
p1_count: 2
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/admin/overview_live.ex"
target_fingerprint: "sha256:a705f4740fcd7ee61987bb21f13bc0b71dc5a2655a0bec6bf50ed59786dffe55"
target_path: /Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/admin/overview_live.ex
timestamp: 2026-11-07T13-10-55Z
slug: owers-web-features-admin-overview-live-ex-97ede660
---
Method: dual-agent (A: design review, B: detector and browser evidence)

Targets: admin overview "Subscription deliveries on closed days" group; account price per delivery; order page subscription block. 1280 and 390, sv UI.

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 2 | Paused subscription's order page reads as running |
| 2 | Match system / real world | 3 | "Payment" vaguer than "Next charge" |
| 3 | User control and freedom | 3 | |
| 4 | Consistency and standards | 2 | 60,00 € vs 60 € (pre-existing) |
| 5 | Error prevention | 2 | Size picker bouquet price vs per-delivery price |
| 6 | Recognition rather than recall | 2 | Row date not shown on the linked subscription page |
| 7 | Flexibility and efficiency | n/a | |
| 8 | Aesthetic and minimalist design | 4 | |
| 9 | Error recovery | 2 | Row names problem, not the fix |
| 10 | Help and documentation | n/a | |
| Total | | 20/32 | Acceptable |

Priority issues
1. [P1] Closed-day row links to a subscription page that doesn't mention the closed date (overview_live.ex closed_day_subscription_row; admin subscription detail). Add weekday to dates; show closed dates on the subscription page beside pause/change day and contact details.
2. [P1] Paused/held subscription's order page hides next-delivery rows and reads as active (order_live.ex subscription block). Show a status row.
3. [P2] Size picker shows bouquet price beside per-delivery price incl. fee (subscription_manager.ex size_options vs price_per_order).
4. [P2] Swedish group titles wrap and orphan the count badge (overview_live.ex attention widget). Shorter title / keep badge with last word.
5. [P2] <div class="contents"> mixed with bare dt/dd in the order page <dl> is invalid HTML (order_live.ex). Use :if on each dt/dd.

Minor: order page money format 60,00 € vs storefront 60 € (pre-existing); closed-day group looks as urgent as failed payments; detector overlay findings all outside changed regions.

Questions: one-tap fix from the row? Should the customer be told about a closed-day delivery?
