---
target: wedding
total_score: 20
max_score: 36
na_heuristics: 7
p0_count: 0
p1_count: 3
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/marketing/weddings_live.ex"
target_fingerprint: "sha256:61c503383a5f5dc1d2de580d8d067123867eeb8c9ffd6d7c6d9a9ae760a4ebc8"
target_path: /Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/marketing/weddings_live.ex
timestamp: 2026-09-19T07-56-42Z
slug: s-web-features-marketing-weddings-live-ex-0c8e2c02
---
# Critique: /weddings (weddings_live.ex)

Score 20/36 (h7 n/a). Acceptable.

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Status | 2 | No lead time/season/availability signal |
| 2 | Real world | 3 | Warm copy; "On request" x6 is vendor-speak; fi "Vieheet" for corsages |
| 3 | Control | 3 | Anchor + lightbox handle Esc/focus well |
| 4 | Consistency | 2 | "starting prices" then no prices; gradient + band alternation off DESIGN.md; fi 3rd person |
| 5 | Error prevention | 2 | Quote path unstructured |
| 6 | Recognition | 2 | "tell me date, venue…" not carried to /contact |
| 7 | Flexibility | n/a | Persuade page |
| 8 | Minimalist | 3 | Calm; prices block is weight without info |
| 9 | Recovery | 2 | No-JS/imgproxy-fail: 15 identical "Wedding flowers" |
| 10 | Help | 1 | No booking lead time, service area, deposit, typical spend |

Specificity: photos are Jennie's; the scaffold (hero/price list/4-step/CTA band) is interchangeable. Jennie absent. Detector: target clean; shared-component findings 3 FP + 1 minor real (layouts.ex:599 text-[10px]).

Priority issues:
1. [P1] Quote handoff dead-ends at generic /contact (:128, :237) — no form, no wedding framing, no reply promise. shape/clarify.
2. [P1] Prices: all nil (:245-253) → "On request" x6 under "these are starting prices" (:162). distill/clarify.
3. [P1] Gallery: filename order, section 4 of 5, alt "Wedding flowers" x15 (:221), credits only in lightbox, no decoration/crowns shown, eden_flowers_3 commented out (:76). layout/polish.
4. [P2] Jennie absent; fi intro 3rd person ("Eden Flowers auttaa"). bolder/clarify.
5. [P3] Drift: gradient hero (:119), band alternation, md:text-6xl override (:123), fi "Vieheet", stale hooks.js:776 comment. polish/harden.

Personas: Jordan — no prices/lead time, fear of "how much?" email. Casey — gallery ~3 screens down; extra hop to /contact. Riley — no-JS raw JPEG tabs; all-nil prices is live state; prod maintenance plug hides page. Couple — date free? travel to venue? deposit? typical spend?

Questions: gallery before prices? gallery grouped by wedding/venue? "Is my date free?" as first ask?
