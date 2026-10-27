---
id: TASK-111
title: Let people send Jennie a message from the funeral and contact pages
status: done
assignee: []
created_date: '2026-10-24 17:44'
updated_date: '2026-10-24 18:03'
labels:
  - spec
  - customers
  - admin
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A shared right-hand drawer (EdenflowersWeb.Marketing.ContactDrawer) with a simple contact form, on the funeral page in place of the mailto link and on the contact page.

**Why:** the "email me" mailto does nothing for people without a mail app set up, so some messages never reach Jennie. A form always works.

Decisions:
- A message to Jennie, not an order. Nothing is stored; Jennie creates any order herself after replying
- Fields: name*, email*, phone, message*. No placeholder text
- Funeral page: "Send me a message" replaces "Email me" as the main button (email-first, as on main); "Or call me on 040 220 9494" stays below
- Contact page: a "Send me a message" button under the intro
- Edenflowers.ContactMessage with a honeypot and its own SendEmails Oban job that emails the sender a copy in their language, bcc Jennie. The email copy is generic, not funeral-specific
- The drawer title turns to "Thank you" once sent; the wedding drawer gets the same fix
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sent message emails the sender a copy in their language, bcc Jennie
- [x] #2 A filled-in honeypot looks sent but nothing goes out
- [x] #3 The email has a Previews scenario and reads well in sv, fi and en
- [x] #4 A message without name, email or message isn't sent
- [x] #5 "Send me a message" on the funeral and contact pages opens a right-hand drawer with the form
<!-- AC:END -->
