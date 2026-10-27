---
id: TASK-138
title: 'Review notes for translators: Gettext strings, other languages and open notes'
status: done
assignee: []
created_date: '2026-10-27 21:26'
updated_date: '2026-10-27 21:41'
labels:
  - admin
  - developers
dependencies: []
priority: medium
type: feature
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Option+Click review box shows which Gettext strings the element renders, with their other-language versions, and marks the page's open notes.

**Why:** translators reviewing e.g. the Finnish site need to see the English and Swedish wording beside what they're correcting, and their notes should point straight at the .po entry instead of rendered text an agent has to search for.

Decisions (grilled 2026-10-27):
- Reverse lookup: the server matches the element's visible text (and its attributes such as placeholder, alt, aria-label) against the page locale's .po entries, %{placeholders} as wildcards. No changes to rendering. Ambiguous matches are all listed; database text (product names) won't match.
- The note box lists each match (domain, msgctxt, msgid) with its en/sv/fi text above the textarea.
- A saved note stores the matched strings; `just review-comments` prints them.
- While Option is held, every reviewer's open notes for the current path are outlined with their text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Option+Clicking translated text shows its domain/msgid and its text in every locale in the note box
- [x] #2 A saved note stores the matched strings and just review-comments prints them
- [x] #3 Holding Option outlines elements with open notes on the current path, showing each note's text
- [x] #4 Option+Clicking an element that has my open note opens it for editing
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Endpoints stay in NoteController rather than AshJsonApi: four endpoints for one picker don't justify the dependency and JSON:API envelopes. Lookup parses the catalogues per request (~96ms). Checked in dev on /fi product page: strings in the box, saved strings in just review-comments, dashed outlines while Option is held, re-click opens the note for editing.
<!-- SECTION:NOTES:END -->
