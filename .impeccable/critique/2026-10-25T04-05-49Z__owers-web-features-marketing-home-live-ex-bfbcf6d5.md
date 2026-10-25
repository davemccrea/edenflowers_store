---
target: homepage reviews section
total_score: 16
max_score: 28
na_heuristics: 7,9,10
p0_count: 0
p1_count: 2
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store.home-reviews/lib/edenflowers_web/features/marketing/home_live.ex"
target_fingerprint: "sha256:e57fb22e79e6f547c3017cec66a104b0737af79c861022756c8b15a1b7892834"
target_path: /Users/david/dev/2_Projects/edenflowers_store.home-reviews/lib/edenflowers_web/features/marketing/home_live.ex
timestamp: 2026-10-25T04-05-49Z
slug: owers-web-features-marketing-home-live-ex-bfbcf6d5
---
Method: dual-agent (A: design review, B: detector + browser evidence)

Target: homepage "What customers say" reviews section (.review-pages), worktree home-reviews.

| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | No sign there are 3 sets or which is up |
| 2 | Match System / Real World | 3 | Real local voices; /en visitors can't read any |
| 3 | User Control and Freedom | 1 | Hover is the only pause; none on touch or keyboard |
| 4 | Consistency and Standards | 3 | Matches hero blur; first infinite loop vs DESIGN.md motion rule |
| 5 | Error Prevention | 2 | Text vanishes mid-read; hidden top set catches pointer/selection |
| 6 | Recognition Rather Than Recall | 2 | Must remember vanished quotes |
| 7 | Flexibility and Efficiency | n/a | Persuade surface |
| 8 | Aesthetic and Minimalist Design | 3 | Calm; 9 repeated flower marks |
| 9 | Error Recovery | n/a | No error states |
| 10 | Help and Documentation | n/a | Not needed |
| Total | | 16/28 | Acceptable |

Design specificity: generic testimonial grid made specific by original sv/fi voice, hero-matching blur and real occasions. Detector: CLI 0 findings; in-page 6 findings, none in section.

Priority issues:
- [P1] Cycle outruns reading (4.9s legible for 60-75 words) and fails WCAG 2.2.2 (no pause for touch/keyboard). Fix: static three plus "More from customers" text control with the same blur; or visible pause, 12-15s step, pause on focus and off screen. /impeccable animate
- [P1] Mobile: section 905px tall vs 844px viewport, swaps while scrolling. Fix: one quote per set below md, or no cycle. /impeccable adapt
- [P2] Hidden sets on top catch pointer, selection, Cmd+F. Fix: pointer-events none on inactive sets / z-index active. /impeccable harden
- [P2] /en visitors get no meaning. Fix: line under heading or italic translation. /impeccable clarify
- [P3] Name-only attribution; two Ainos read as a bug. Fix: add occasion to eyebrow. /impeccable clarify

Personas: Jordan can't read quotes on /en; Sam gets 3 unlabelled lists and no focusable pause; Casey has no hover pause, section taller than viewport.

Minor: ~0.4s blank dip at handover; consider serif italic for quotes; keyframes tied to 3 sets; detector's paused reading was my own frozen tab.

Questions: one large pull-quote at a time? Server-side random three instead of motion?
