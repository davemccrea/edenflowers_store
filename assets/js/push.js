// @ts-check

// Web Push for the installed admin app: subscribing this device to new-order
// notifications, and clearing them (and the icon badge) once the app is open.
// The service worker lives at /admin-sw.js.

export const pushSupported = () =>
  "serviceWorker" in navigator &&
  "PushManager" in window &&
  "Notification" in window;

// Every admin page registers the worker. Notifications still wait for the
// device to turn them on.
export const registerAdminWorker = () =>
  navigator.serviceWorker.register("/admin-sw.js", { scope: "/admin" });

const existingAdminWorker = () =>
  navigator.serviceWorker.getRegistration("/admin");

/** @returns {Promise<PushSubscription | null>} */
export async function currentSubscription() {
  const registration = await existingAdminWorker();
  return registration ? registration.pushManager.getSubscription() : null;
}

/**
 * Saves this device's subscription again, in case the server forgot it (say
 * after a one-off 404 from the push service) or the browser replaced it.
 *
 * @param {any} hook
 * @returns {Promise<PushSubscription | null>}
 */
export async function resyncSubscription(hook) {
  const subscription = await currentSubscription().catch(() => null);
  if (subscription) hook.pushEvent("push_subscribed", subscription.toJSON());
  return subscription;
}

/** @param {string} base64url */
const decodeKey = (base64url) => {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
};

/**
 * Asks for permission, subscribes this device and saves the subscription
 * through the hook's LiveView. Resolves to the state the device ends up in.
 *
 * @param {any} hook
 * @param {string} vapidPublicKey
 * @returns {Promise<"on" | "off" | "denied" | "error">}
 */
export async function subscribeDevice(hook, vapidPublicKey) {
  try {
    // Asked first, before any other await: iOS only shows the prompt while
    // the tap that triggered it is still being handled.
    const permission = await Notification.requestPermission();
    if (permission === "denied") return "denied";
    if (permission !== "granted") return "off";

    await registerAdminWorker();
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: decodeKey(vapidPublicKey),
    });

    const reply = await hook.pushEvent(
      "push_subscribed",
      subscription.toJSON(),
    );
    if (reply?.ok) return "on";

    await subscription.unsubscribe();
    return "error";
  } catch {
    return "error";
  }
}

/** @param {any} hook */
export async function unsubscribeDevice(hook) {
  const subscription = await currentSubscription();
  if (!subscription) return;

  await hook.pushEvent("push_unsubscribed", {
    endpoint: subscription.endpoint,
  });
  await subscription.unsubscribe();
}

// Opening the app counts as seeing the new orders.
export async function clearOrderAlerts() {
  try {
    await navigator.clearAppBadge?.();
    if (!("serviceWorker" in navigator)) return;

    const registration = await existingAdminWorker();
    if (!registration) return;

    const notifications = await registration.getNotifications();
    notifications.forEach((notification) => notification.close());
  } catch {
    // A missing badge or notification API is nothing to report.
  }
}
