// Service worker for the installed admin app, registered with scope /admin.
// It shows new-order notifications, keeps the app icon's badge in step, and
// covers the app's launch with a loading screen. Nothing is cached: LiveView
// needs its socket anyway.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) =>
  event.waitUntil(self.clients.claim()),
);

// Opening the app (or iOS reloading it after evicting it) shows a blank screen
// until the server's first byte arrives. Answering that launch at once with
// this page, which then asks for the real one, keeps it on screen instead:
// the browser holds the old page until the new one paints. The dots only show
// if the wait is long enough to notice.
const launchScreen = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#BDCCC3">
<title>Eden Admin</title>
<style>
  html, body { height: 100%; margin: 0; background: oklch(99% 0.004 75); }
  body { display: grid; place-items: center; }
  .dots { display: flex; gap: 10px; opacity: 0; animation: appear 200ms 400ms forwards; }
  .dots span {
    width: 10px; height: 10px; border-radius: 50%;
    background: oklch(0.3684 0.0478 156.76);
    animation: pulse 1.2s ease-in-out infinite;
  }
  .dots span:nth-child(2) { animation-delay: 150ms; }
  .dots span:nth-child(3) { animation-delay: 300ms; }
  @keyframes appear { to { opacity: 1; } }
  @keyframes pulse { 0%, 100% { opacity: 0.25; } 50% { opacity: 1; } }
  @media (prefers-reduced-motion: reduce) {
    .dots span { animation: none; opacity: 0.6; }
  }
</style>
</head>
<body>
<div class="dots" role="status" aria-label="Loading"><span></span><span></span><span></span></div>
<script>location.replace(location.href);</script>
</body>
</html>`;

// The launch screen's own request for the real page must reach the network,
// or it would answer itself forever. It is a window by then, but a moment's
// memory covers a browser that doesn't list it yet.
let launchScreenServedAt = 0;

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.mode !== "navigate" || request.method !== "GET") return;

  event.respondWith(
    (async () => {
      const windows = await self.clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });
      const justServed = Date.now() - launchScreenServedAt < 10_000;

      if (windows.length > 0 || justServed) return fetch(request);

      launchScreenServedAt = Date.now();
      return new Response(launchScreen, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    })(),
  );
});

self.addEventListener("push", (event) => {
  const { title, body, tag, url } = event.data.json();

  event.waitUntil(
    (async () => {
      // A retried push carries the same tag, so it replaces its notification
      // rather than adding one.
      await self.registration.showNotification(title, {
        body,
        tag,
        data: { url },
        icon: "/web-app-manifest-192x192.png",
      });

      // The badge counts the order notifications still in Notification Centre.
      const shown = await self.registration.getNotifications();
      await navigator.setAppBadge?.(shown.length);
    })(),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(
    event.notification.data?.url ?? "/admin",
    self.location.origin,
  ).href;

  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: "window" });
      const admin = windows.find((client) =>
        new URL(client.url).pathname.startsWith("/admin"),
      );

      if (admin) {
        await admin.focus();
        const navigated = await admin.navigate(url).catch(() => null);
        if (navigated) return;
      }

      await self.clients.openWindow(url);
    })(),
  );
});
