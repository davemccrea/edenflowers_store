---
id: TASK-137
title: 'Review comments: reviewers Option+Click any element to leave a note'
status: done
assignee: []
created_date: '2026-10-27 20:40'
updated_date: '2026-10-29 07:28'
labels:
  - admin
  - developers
  - spec
dependencies: []
priority: medium
type: feature
ordinal: 270000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reviewers leave notes on any element of the live site by Option+Clicking it; the note and the element's context are stored for agents to work through before launch.

**Why:** pre-launch feedback arrives as screenshots and messages that are hard to map to code; a note tied to the exact element, page and (in dev) HEEx source turns each into a fixable ticket.

Decisions (grilled 2026-10-27):
- `User.reviewer` flag, set only in the DB like `admin`; admins count as reviewers (`can_review?`).
- `Edenflowers.Feedback.Note`: body, path, locale, viewport, selector, element text, truncated outerHTML, HEEx source (dev only), app version, author, `resolved_at`.
- One Option+Click picker for all envs, replacing the dev picker. Prod: reviewers only. Dev: everyone copies the source reference; reviewers also get the comment box.
- Minimal popover, Cmd+Enter saves, Esc cancels; English only; desktop only.
- fetch POST to a controller so controller pages work too.
- No UI for reading: `just review-comments` prints open notes from prod over rpc; `just resolve-review-comment <id>` resolves without a backup (CLAUDE.md exemption).
- Permanent, flag-gated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A reviewer can Option+Click any element in prod and save a note with its context
- [x] #2 In dev, Option+Click still copies the source reference for everyone
- [x] #3 Non-reviewers in prod see no picker
- [x] #4 `just feedback` prints open notes and `just resolve-feedback` resolves them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built and checked in dev: Option+Click, save with Cmd+Enter, Esc cancels, `just review-comments local` prints the note with its HEEx source. The production picker path (no dev annotations, any element pickable) and the prod rpc recipes are untested until deployed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 21:05

---

Built, rebased on the improved dev picker, and checked in dev. Left for David: deploy, set reviewer = true on reviewers in prod (after just backup), Option+Click a page in prod, then check just review-comments and just resolve-review-comment, and AC 4.

---

author: @claude
created: 2026-10-29 07:28

---

David ran just feedback and just resolve-feedback against production; both work. AC 4 reworded for the renamed recipes.

---
<!-- COMMENTS:END -->
