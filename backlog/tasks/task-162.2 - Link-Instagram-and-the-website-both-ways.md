---
id: TASK-162.2
title: Tag the Instagram and Facebook bio links to the site
status: done
assignee: []
created_date: '2026-11-01 14:07'
updated_date: '2026-11-09 12:32'
labels: []
dependencies: []
parent_task_id: TASK-162
type: task
ordinal: 299000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Instagram is the plan's main channel, and orders from the Instagram bio or the Facebook page only show up by source in Umami if those links are tagged.

Decisions (grilled 2026-11-01):
- The Instagram bio and the Facebook page's website field link to the bare homepage, https://edenflowers.fi/, so the site picks the language from the browser. The root redirect keeps the query string, so the tags survive.
- UTM tags from the admin share drawer: source instagram / facebook, medium bio.
- The storefront footer already links to Instagram and Facebook (Socials, Business.social_urls/0); nothing to build.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Instagram bio and Facebook page link to the site with UTM tags
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 16:07

---

2026-11-01: Grilled with David. Left for Jennie or David: make both links in the share drawer and paste them into the Instagram bio and the Facebook page.

---

author: @claude
created: 2026-11-09 12:32

---

2026-11-09: the UTM-tagged links are in the Instagram bio and the Facebook page. Closed.

---
<!-- COMMENTS:END -->
