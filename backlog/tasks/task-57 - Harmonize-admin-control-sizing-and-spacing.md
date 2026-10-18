---
id: TASK-57
title: Harmonize admin control sizing and spacing
status: done
assignee: []
created_date: '2026-10-18 21:52'
updated_date: '2026-10-18 21:52'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: refactor
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bring admin form controls into a consistent visual scale.

**Why:** Oversized checkboxes and mismatched label and control proportions make the admin feel uneven for Jennie. A shared sizing and spacing treatment makes forms calmer and easier to scan.

Use the existing admin field scale: 14px labels, 16px checkbox and radio markers, compact switches, and aligned inner spacing for selects and radio options. Preserve square checkbox and field shapes, circular radios, visible keyboard focus, and generous touch targets. Apply the treatment through shared admin styles.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Checkboxes use 16px markers matching radios, and switches use the compact size.
- [x] #2 Form labels use the 14px field text scale, with consistent choice gaps and select/radio-option inner spacing.
- [x] #3 Keyboard focus remains visible and touch-screen targets remain at least 44px.
- [x] #4 Representative admin screens render without horizontal page overflow on desktop, tablet, and mobile.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in assets/css/admin.css using existing daisyUI size variants and Tailwind spacing utilities.

Verification: source .env && mix tailwind edenflowers; git diff --check; Playwright checks across product forms, order forms, fulfillment settings, and product listings at desktop, tablet, and mobile sizes. Checked checkbox interaction, keyboard focus, control dimensions, touch targets, and page overflow.
<!-- SECTION:FINAL_SUMMARY:END -->
