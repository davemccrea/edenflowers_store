---
id: TASK-9.2
title: Push a notification to the admin when a paid order is placed
status: done
assignee: []
created_date: '2026-10-15 23:06'
updated_date: '2026-10-18 08:25'
labels: []
dependencies:
  - TASK-9.1
parent_task_id: TASK-9
type: feature
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Send a Web Push notification to every admin device that has opted in whenever a customer places a paid order, so Jennie hears about same-day orders straight away. Tapping the notification opens the order in the admin.

On iOS, Web Push only works for home-screen apps, so this depends on the installable admin app (01).

#### Subscribing

The setting is per device, so it lives in its own "This device" section on `/admin/account`, and the Overview page offers it once on an installed app that hasn't been asked yet.

**Account page:** a second card below the existing profile card, styled the same (`bg-base-100 border-base-content/12 border p-4 sm:p-5`), so device settings don't mix with account details.

```
┌ This device ─────────────────────────────┐
│ New order notifications          [ ●━━ ] │
│ Shown on this phone only.                │
└──────────────────────────────────────────┘
```

- The switch is a daisyUI `toggle toggle-primary` checkbox with `role="switch"`, labelled by "New order notifications" and described by the help line.
- Turning it on asks for notification permission (the tap is the user gesture iOS requires), subscribes through the service worker's `PushManager` with the VAPID public key, and saves the subscription. Turning it off unsubscribes in the browser and deletes the subscription.
- It shows this device's state, read from `PushManager.getSubscription()` in a JS hook, not the account's. Jennie may have the phone subscribed and the laptop not. Keep it disabled until the hook has checked, so it never flashes the wrong state.
- The help line changes with the state:
  - push not supported (Safari outside the installed app): no switch, "Add Eden Admin to your home screen to get notifications."
  - permission denied: switch disabled, "Notifications are blocked. Allow them for Eden Admin in your phone's Settings."
  - subscribing failed: switch back off, error text "Couldn't turn on notifications. Try again."

**Overview nudge:** a card at the top of `/admin` with "Get new orders on this phone", "Same-day orders arrive straight away." and two buttons, "Not now" and "Turn on".

```
┌──────────────────────────────────────────┐
│ 🔔 Get new orders on this phone          │
│    Same-day orders arrive straight away. │
│              [Not now]  [Turn on]        │
└──────────────────────────────────────────┘
```

- Shown only when the page runs as the installed app (`matchMedia("(display-mode: standalone)")`), push is supported, and `Notification.permission` is `"default"`. The hook decides on the client, so the card starts hidden and never flashes on desktop.
- "Turn on" runs the same subscribe flow as the Account switch and hides the card whatever the outcome; the Account page is where to retry.
- "Not now" hides it on this device for good (`localStorage`, in a try/catch). The Account switch is still there.
- Share the subscribe/unsubscribe code between the two hooks rather than duplicating it.

#### Push subscription resource

- A new Ash resource holding `endpoint` (unique), `p256dh`, `auth` and the admin `user` it belongs to. Re-subscribing with an existing endpoint upserts it.
- Only admins can create, read or destroy subscriptions, and only their own.
- Generate the migration; don't hand-write it.

#### Sending

- Send from the domain, not a LiveView: an AshOban trigger on `Order`, enqueued by a change on `:finalize_checkout` alongside `ScheduleConfirmationEmail`. The push goes out after commit and a failed push never fails checkout.
- `:place_custom` (Jennie's own orders) and subscription occurrences don't notify. She already knows about them.
- Payload: title "New order #<order_reference>", body with the fulfillment date, method (delivery or pickup) and total, plus the URL `/admin/orders/<id>`. Mark it as same-day in the title when the fulfillment date is today.
- Push to every saved subscription. A `404` or `410` from the push service means the subscription is gone: delete it. Other failures retry through Oban.
- Use an existing Elixir Web Push library (`web_push_elixir` or similar) rather than writing the VAPID/encryption code.

#### Service worker

- Served at `/admin/sw.js` and registered from the admin layout only, so its scope is `/admin` by default without a `Service-Worker-Allowed` header. It holds nothing sensitive, so it can be a plain static file.
- It only handles `push` (show the notification and update the badge) and `notificationclick` (focus an open admin window and navigate it to the URL, or open one). No caching or fetch handler: LiveView needs the socket anyway.

#### App badge

The installed app's icon shows how many new orders Jennie hasn't looked at yet.

- On `push`, after showing the notification, set the badge to the number of order notifications still in Notification Centre: `navigator.setAppBadge((await self.registration.getNotifications()).length)`. Tag each notification with the order id so a retried push replaces its notification instead of adding one.
- When an admin page becomes visible (`visibilitychange` to visible, and on load), close the service worker's notifications and call `navigator.clearAppBadge()`. Opening the app means she's seen them.
- Nothing is stored server-side or in IndexedDB; Notification Centre is the count.
- Skip silently where `setAppBadge` doesn't exist (desktop Firefox).

#### Config

- `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` and a `VAPID_SUBJECT` (`mailto:` address) in runtime config. Production values go in phoenix-ansible; a human adds those.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Turning on the "This device" switch on an installed admin app saves a subscription; turning it off deletes it
- [ ] #2 The switch shows each device's own state: on for the subscribed phone, off for an unsubscribed laptop
- [ ] #3 Unsupported and blocked states show their help text in place of a working switch
- [ ] #4 The Overview card appears once on a freshly installed app, "Turn on" subscribes, and neither button brings it back
- [ ] #5 The Overview card never appears in a normal browser tab
- [ ] #6 A customer checkout that completes payment sends one notification to each subscribed device
- [ ] #7 A same-day order is marked as same-day in the notification
- [ ] #8 Tapping the notification opens `/admin/orders/<id>` in the admin app
- [ ] #9 Two orders arriving while the app is closed show a badge of 2 on the home-screen icon; opening the app clears it and the notifications
- [ ] #10 Orders from `:place_custom` and subscription occurrences don't notify
- [ ] #11 An expired subscription (`410`) is deleted and doesn't stop the others being sent
- [ ] #12 A failing push service doesn't fail or slow checkout
- [ ] #13 Non-admins can't create or read push subscriptions (policy test)
- [ ] #14 User-facing strings use `~t` and are translated
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-17 18:45

---

Implemented 2026-10-15, with these departures from the spec above:

- **`web_push_ex` for encryption and VAPID.** It does `aes128gcm` (which Apple requires; `web_push_elixir` only does the old `aesgcm`) and leaves sending to us, so `Edenflowers.WebPush` posts with Req. A test decrypts what reaches a stubbed push service and verifies the VAPID token.
- **Service worker at `/admin-sw.js`**, a plain static file, registered with scope `/admin`. A script at the root may claim any scope below it, so there's no `/admin/sw.js` route and no header.
- **Help text says "this device"**, not "this phone", since the switch also shows on a laptop.
- **A plain Oban worker, not an AshOban trigger.** The change inserts `PushNewOrder` in the finalize transaction; there's no trigger condition to poll for.
- Only devices whose user is still an admin are notified.
- Without `VAPID_PUBLIC_KEY` the setting and offer are hidden and nothing is queued, so staging stays quiet.

Still to check by hand on an iPhone: install, subscribe, receive, badge, tap-through.

---
<!-- COMMENTS:END -->
