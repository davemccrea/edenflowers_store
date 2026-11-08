---
target: Shared admin timeline and stable history event identities
total_score: 28
max_score: 32
na_heuristics: 5,9
p0_count: 0
p1_count: 0
target_identity: "file:/Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/admin/components/components.ex"
target_fingerprint: "sha256:1c12e3fb94cb55894abafe4d7522a758e1950fb7d0e7a99146f1330526a9419f"
target_path: /Users/david/dev/2_Projects/edenflowers_store/lib/edenflowers_web/features/admin/components/components.ex
timestamp: 2026-11-07T22-56-30Z
slug: b-features-admin-components-components-ex-c67efb6a
---
Method: dual-agent (A: /root/timeline_design_review · B: /root/timeline_evidence_review)

The stable-identity and shared-timeline work is complete. History uses record-derived version, payment and document event IDs, keyed rendering, and native details whose expanded state stays attached to the same record. History and Pass it on share `timeline` and `timeline_item` for dots, rails, spacing and branches. History stays newest first for operational scanning; Pass it on stays source first for following the handoff.

The design remains appropriate to Eden Flowers: warm paper, restrained green, clear sans typography and meaningful recipient/card relationships. Its purpose is quick administration, and the quiet connected-dot treatment supports that purpose.

| # | Nielsen heuristic | Score | Evidence |
|---|---|---|---|
| 1 | Visibility of system status | 3/4 | Latest history event and current order are highlighted; native disclosure updates immediately. |
| 2 | Match with the real world | 4/4 | Concrete event, payment, card and recipient language. |
| 3 | User control and freedom | 4/4 | Keyboard disclosure and direct related-order links; no imposed workflow. |
| 4 | Consistency and standards | 4/4 | Shared geometry; connector correction independently confirmed. |
| 5 | Error prevention | n/a | This review concerns reading and disclosure, without destructive input. |
| 6 | Recognition rather than recall | 3/4 | Names, references, timestamps and card statuses preserve context; narrow-screen truncation remains. |
| 7 | Flexibility and efficiency | 3/4 | Keyboard controls and inline details support quick inspection. |
| 8 | Aesthetic and minimalist design | 4/4 | Simple hierarchy, restrained markers and progressive disclosure. |
| 9 | Error recovery | n/a | No timeline-specific recovery operation in the reviewed interaction. |
| 10 | Help and documentation | 3/4 | Familiar labels and the missing-source message explain the presented states. |
| Total | | 28/32 — Good | Eight applicable heuristics. |

Both reviewers independently found one priority issue: P2, the History connector stopped 22px short of the next marker after extraction. The connector's containing block excluded the list item's inter-event padding. It was corrected by positioning flat connectors against the full list item and keeping a separate positioned body for nested branches. Reviewer A confirmed the fix at 390px and 1440px, collapsed and expanded. Final connectors remain hidden and branch rails remain intact. No unresolved Priority Issue remains, and no P0 or P1 issue was found. This correction is complete; no further command is needed for it.

What works: native details preserve recognizable keyboard behavior and visible focus; stable namespaced IDs preserve the exact event during updates; the branch tree conveys sources without repeating order numbers or incoming card codes. Cognitive load is low, with no clear checklist failure or target decision point containing more than four competing actions. The experience supports a quick scan followed by reassurance from inline details.

For the administrator, direct links and concise event headings support efficient inspection. For a keyboard or accessibility-dependent reader, Enter opens, Space closes, focus stays on the summary, and decorative rails are hidden from assistive technology. No keyboard blocker was found. A screen-reader announcement session was not performed.

Optional observations, separate from required fixes: single-line disclosure targets are 20px high and could gain a taller mobile hit area; empty order histories currently show a blank panel under their heading; long Pass it on customer names truncate at 320px. These are existing or optional refinements, not blockers introduced by this extraction. Future work can choose compact versus taller rows and truncation versus wrapping when those aspects are in scope.

Mechanical evidence: the CLI detector reported zero source findings across six markup targets. The browser overlay flagged a code-label padding false positive caused by its screen-reader-only child, an existing compact recipient badge, and the configured Open Sans usage. None established a timeline defect. Sampled timeline secondary text contrast was 5.32:1 and Used badges 5.09:1. Both timelines fit at 390px/1440px and in the half-width/DPR-2 reflow simulation; native browser toolbar zoom was unavailable, so this is not represented as a native zoom test. Overlay script injection executed, but the headless browser provides no persistent user-visible Human tab.

Implementation verification: 174 focused tests passed across the affected order, subscription, invoice, promotion and order-domain cases. A separate connected-browser regression at 390px and 1440px proved that the original details DOM node remained connected and open after a new event was prepended, the new event started closed, IDs stayed unique, and there was no horizontal overflow. Compiler, lint, formatting and translation checks passed.

Review evidence is retained under /private/tmp/timeline-a-confirm-*, /private/tmp/eden-timeline-assessment-b/, and /private/tmp/eden-timeline-connected-*. Assessment A did not access detector findings. Assessment B held its findings until Assessment A completed. Static fixture limits were supplemented by the connected-browser regression.

Questions skipped: one Priority Issue, resolved; no unresolved Priority Issues remain.
