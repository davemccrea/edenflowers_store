---
target: home
total_score: 17
max_score: 28
na_heuristics: 7,9,10
p0_count: 1
p1_count: 3
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/marketing/home_live.ex"
target_fingerprint: "sha256:169dab84c6277cb7bccb079326bd12e9152d2baa6499a6e9964d7c5bd5bf13f5"
target_path: /Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/marketing/home_live.ex
timestamp: 2026-09-19T07-17-25Z
slug: owers-web-features-marketing-home-live-ex-bfbcf6d5
---
# Critique: home (lib/edenflowers_web/features/marketing/home_live.ex)

Method: dual-agent. Browser overlay was skipped because Claude in Chrome is not set up; the detector ran in URL mode and screenshots came from Playwright.

## Heuristics (17/28, Acceptable; 7, 9 and 10 n/a)
1 Status 2 · 2 Real world 2 · 3 Control 3 · 4 Consistency 2 · 5 Error prevention 2 · 6 Recognition 3 · 8 Aesthetic 3

## Priority issues
- [P0] Condolences tile is a placehold.co grey box (home_live.ex:166). In fi/sv, "Kondoleanser"/"Suruvalittelut" means sympathy messages, not funeral flowers. Fix: use a real photo or drop the tile, and rename it. Commands: harden, clarify.
- [P1] Hero h1 is text-white over the photo with no scrim (home_live.ex:28-35). This breaks the Gradient-For-Legibility Rule (DESIGN.md:216) and is hard to read over cloud/blooms. Fix: add the bottom-up from-black/50 via-black/15 scrim. Command: polish.
- [P1] Copy argues instead of showing, and Jennie is absent. Pull quote "Crafted for those with discerning taste" (:137); brand "we"; "delivery rates among the lowest in Vaasa" (:118) is a price claim flagged for removal. Fix: replace the forest pull-quote band with Jennie in the first person and her portrait; cut the rates line. Command: clarify.
- [P1] Key promises are missing: same-day delivery before 14:00, funeral delivery to churches in Vaasa/Korsholm. "Made in Minimossen" is a <p> eyebrow used as the aria-labelledby target, with no h2. Fix: add a real h2 and 2-3 plain facts; label the map pin. Command: layout.
- [P2] The page structure could be any florist's (hero / Favourites / 3 Services tiles / quote / logos), and there is no way in by occasion, although customers arrive knowing the occasion. Command: shape.

## Detector
Source is nearly clean. False positives: broken-image at core_components.ex:719/726 (docstring text), #000000 at :671 (the replacement that removes it). Real: text-[10px] at layouts.ex:599, image-hover scale at core_components.ex:920/960 (not documented in DESIGN.md), width transition on embla dots (app.css:584-602). URL mode: low-contrast white text on the hero agrees with P1 above. italic-serif-display, overused-font, kicker-above-heading and tight-leading are all mandated by DESIGN.md, so they are false positives.

## Personas
Funeral orderer on a phone reaches the grey placeholder ~4000px down; nothing says "church" or "14:00"; they phone. Casey: first screen has no delivery promise; the watermark flower overlaps the eyebrow at 390. Riley: no empty state if featured products = 0; logos open new tabs without warning.

## Minor
Footer "Built with ❤️" breaks the no-hearts rule; the "15% off" newsletter promise is unconfirmed in PRODUCT.md. The "Services" eyebrow repeats "Beyond the storefront". The desktop carousel reads as a static row of 3. Tile hover stacks 3 effects.
