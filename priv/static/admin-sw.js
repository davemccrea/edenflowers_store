// Service worker for the installed admin app, registered with scope /admin.
// It only shows new-order notifications and keeps the app icon's badge in step.
// No fetch handler or caching: LiveView needs its socket anyway.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) =>
  event.waitUntil(self.clients.claim()),
);

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
