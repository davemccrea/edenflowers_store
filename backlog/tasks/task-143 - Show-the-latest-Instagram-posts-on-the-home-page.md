---
id: TASK-143
title: Show the latest Instagram posts on the home page
status: needs-triage
assignee: []
created_date: '2026-10-29 07:59'
labels:
  - spec
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 278000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The home page shows the shop's latest Instagram posts, fetched by our server so the section stays current with no manual work.

**Why:** The Instagram feed is the freshest record of the shop's work. Showing it on the home page keeps the page lively and leads visitors to follow the account, without Meta scripts or cookies on the site.

## Approach (option 3 of three considered)

Rejected: Instagram's embed code (manual per post, loads Meta trackers so needs consent and a privacy policy change, off-brand styling) and paid widgets (Behold, LightWidget, Elfsight: third-party script, same privacy questions, limited styling).

- **Setup:** the account must be a Business or Creator account. Create a Meta developer app with "Instagram API with Instagram Login" and get a long-lived access token. App Review shouldn't be needed when we only read our own account.
- **Ash resource:** `InstagramPost` (caption, permalink, image, media type, posted at) with a read action for the latest posts.
- **Oban cron sync:** every hour or so, fetch recent media with `Req` and save new posts. Instagram's `media_url` expires, so download each image into our own storage and serve it through imgproxy like product photos. Reels use `thumbnail_url`; carousels use their first child.
- **Token refresh:** the long-lived token lasts 60 days, so a cron job renews it monthly. If the token or sync fails, the section hides itself rather than breaking the page.
- **Section:** a grid or the existing carousel pattern, each post linking to Instagram, plus a follow link.

## Open questions (grill before implementing)

- How many posts, and grid or carousel?
- Show captions? They're in one language only, on a page served in en/fi/sv.
- Where on the page does the section go?
- Include reels, or photos only?
- Should admins be able to hide a post?
- Where does the token live (env var vs database), and who gets told when renewal fails?
- Where the section sits in the privacy policy (TASK-116), if anywhere.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The home page shows the latest Instagram posts, each linking to the post on Instagram
- [ ] #2 New posts appear without anyone touching the site
- [ ] #3 No Meta script, cookie or image request reaches visitors' browsers
- [ ] #4 The access token renews itself before it expires
- [ ] #5 If syncing fails, the home page still renders, without the section or with the last synced posts
<!-- AC:END -->
