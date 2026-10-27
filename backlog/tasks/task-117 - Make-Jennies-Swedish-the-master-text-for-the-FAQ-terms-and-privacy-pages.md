---
id: TASK-117
title: 'Make Jennie''s Swedish the master text for the FAQ, terms and privacy pages'
status: ready-for-human
assignee: []
created_date: '2026-10-24 19:28'
updated_date: '2026-10-27 08:48'
labels:
  - spec
  - customers
dependencies:
  - TASK-114
  - TASK-115
  - TASK-116
priority: medium
type: task
ordinal: 238000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The FAQ, terms and privacy pages read in Swedish exactly as Jennie wrote them, with English and Finnish rewritten to match.

**Why:** The terms have legal weight in Swedish and Finnish, and Jennie customers mostly read Swedish. Agent-drafted Swedish is not good enough to stand as the shop word.

Decided in grilling (2026-10-24):
- Jennie corrects the agent-drafted Swedish msgstrs for faq_live, the terms page and the privacy page.
- Her Swedish then becomes definitive: an agent updates the English msgids and the Finnish msgstrs to say the same thing, without changing her Swedish.
- Afterwards, clear fuzzy entries in all three .po files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie has corrected the Swedish on all three pages
- [ ] #2 English and Finnish say the same as her Swedish, and no fuzzy entries are left
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 19:25

---

FAQ inline-link copy and checker distance/price wording now introduce new/split source strings. Swedish/Finnish translations have not been generated (opt-in); changed fragments fall back to English. Include these phrases in the next language pass and review the complete linked sentences, not just isolated anchor labels. See TASK-115 notes.

---

author: @pi
created: 2026-10-27 08:48

---

Filled 78 missing Swedish translations and 78 missing Finnish translations for the current Privacy, Terms and FAQ pages, preserving existing non-empty translations. All 53 page tests pass, including translated privacy copy and complete linked FAQ sentences. Current page strings have no missing or fuzzy Swedish/Finnish translations. Jennie still needs to review the Swedish master text; neither acceptance criterion is claimed complete.

---
<!-- COMMENTS:END -->
