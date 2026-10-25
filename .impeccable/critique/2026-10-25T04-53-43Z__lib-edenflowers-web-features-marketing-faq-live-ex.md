---
target: FAQ page pattern
total_score: 21
max_score: 32
na_heuristics: 5,9
p0_count: 1
p1_count: 2
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store.faq-overhaul/lib/edenflowers_web/features/marketing/faq_live.ex"
target_fingerprint: "sha256:c7025e01fcb42e92ccca97c7c10b4195dbaa4caa795c63f3f9915dc652b71ba0"
target_path: /Users/david/dev/2_Projects/edenflowers_store.faq-overhaul/lib/edenflowers_web/features/marketing/faq_live.ex
timestamp: 2026-10-25T04-53-43Z
slug: lib-edenflowers-web-features-marketing-faq-live-ex
---
Method: dual-agent (A: design review · B: detector + browser)

## Verdict on the pattern
Keep the accordion, drop the sticky mobile section strip. Collapsed page is under 3 phone screens; headings already index it. All-open long-form is the close second; tabs and search rejected.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | No active-section state |
| 2 | Match System / Real World | 4 | Customer's words, live numbers |
| 3 | User Control and Freedom | 3 | Strip keeps stale scroll after jumps |
| 4 | Consistency and Standards | 3 | Nav ignores honey-underline index convention |
| 5 | Error Prevention | n/a | Read-only page |
| 6 | Recognition Rather Than Recall | 2 | Mobile strip hides 4 of 7 sections |
| 7 | Flexibility and Efficiency | 2 | iOS find can't reach closed answers; no per-question anchors |
| 8 | Aesthetic and Minimalist Design | 3 | Strip duplicates headings |
| 9 | Error Recovery | n/a | No error states |
| 10 | Help and Documentation | 2 | Dead-ends with no "ask me" |
| **Total** | | **21/32** | **Acceptable** |

## Design Specificity
Copy authored (first person, live data, local answers); visuals are a generic help-centre template. Detector: exit 0; advisories text-[1.0625rem] faq_live.ex:287, text-[10px] layouts.ex:769. Browser overlay: 22 layout-transition (daisyUI collapse, false positive), 1 overused-font (brand Open Sans, false positive).

## Priority Issues
- [P0] Invisible keyboard focus on summaries (FAQ and product page). Fix: focus-visible outline in primary.
- [P1] Sticky mobile strip obscures focused/anchored content (focused summary at 77px under 114px of chrome). Fix: remove strip on mobile, revert --shy-header-offset.
- [P1] Mobile strip hides sections, 22px tap targets, no scroll affordance. Fix: static wrapped list ≥44px or none.
- [P2] Dead end and buried delivery/same-day questions. Fix: closing cream "Ask me" callout; open Delivery or add Most asked.
- [P2] No active section on desktop sidebar. Fix: IntersectionObserver + honey underline.

## Persona Red Flags
Casey: 22px top-of-screen links, strip jumps on scroll direction change, delivery is question 4. Jordan: doesn't know strip scrolls, no human fallback. Sam: invisible focus, focus obscured by strip.

## Minor Observations
Cancellation spread over 3 sections; lone "Get in touch" lines; no worked delivery price example; no per-question anchors.

## Questions to Consider
Why hide answers shorter than a text? Should mid-checkout answers live at checkout? Would we build the sticky strip mobile-first?
