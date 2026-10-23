// Admin page changes animate like a native app (admin.css). Only link and
// server navigations animate. Browser back and forward swap instantly, as
// does every other diff.
let pendingAdminTransition = null;

const adminPath = (href) =>
  new URL(href, location.href).pathname.replace(/\/$/, "");

const isInside = (path, ancestor) => path.startsWith(`${ancestor}/`);

const isSectionList = (path) => /^\/admin\/[^/]+$/.test(path);

// As on iOS: opening something pushes, even across sections (a customer's
// order), going up to a page above pops, and switching to another section's
// list is like changing tabs, which fades through. Overview is another tab
// beside the sections, though every admin path sits under it.
function transitionBetween(from, to) {
  if (from === to) return null;
  if (to === "/admin") return "fade";
  if (from === "/admin") return isSectionList(to) ? "fade" : "push";
  if (isInside(to, from)) return "push";
  if (isInside(from, to)) return "pop";
  if (isSectionList(to)) return "fade";
  return "push";
}

// A link can name its own transition where the hierarchy can't tell, such as
// the previous and next arrows between orders. Captured ahead of LiveView's
// click handler, which starts the navigation.
let linkTransition = null;

document.addEventListener(
  "click",
  (event) => {
    linkTransition =
      event.target.closest?.("a[data-transition]")?.dataset.transition ?? null;
  },
  true,
);

window.addEventListener("phx:page-loading-start", ({ detail }) => {
  if (detail.kind !== "redirect") return;
  // location still holds the page being left.
  pendingAdminTransition =
    linkTransition ??
    transitionBetween(adminPath(location.href), adminPath(detail.to));
  linkTransition = null;
});
window.addEventListener("phx:page-loading-stop", () => {
  pendingAdminTransition = null;
});

// LiveView applies updates in the order they arrive. A view transition delays
// its update by a frame, so any update that arrives meanwhile (such as a Cinder
// table's rows) waits behind it. Applied early, LiveView would discard it as
// belonging to the page being left.
//
// Arguably a LiveView bug (as of 1.2.12): a diff queued while a delayed join
// patch is pending gets stamped with the old joinCount, which is only bumped
// inside `start`, and is then dropped as stale. If a later LiveView stamps it
// correctly, this queue can go. To check, remove it, navigate to a Cinder table
// page with liveSocket.enableDebug() on and look for "discarded diff from
// previous join".
let heldPatches = null;

// LiveView swaps in the new page inside `start`, so the view transition
// captures the old page, runs `start` and animates to the result.
export function onDocumentPatch(start) {
  if (heldPatches) return heldPatches.push(start);

  const kind = pendingAdminTransition;
  pendingAdminTransition = null;

  // An open drawer or modal would be snapshotted mid-page, so those navigations
  // swap instantly, as they did before. The navigation drawer is the exception:
  // it slides away in its own snapshot (admin.css).
  // Only the installed app animates, as a native one would. In a browser tab
  // pages swap straight away, as on most web apps.
  const animate =
    kind &&
    document.startViewTransition &&
    document.querySelector(".admin-theme") &&
    matchMedia("(display-mode: standalone)").matches &&
    !document.querySelector("dialog[open]:not(#admin-nav-drawer-dialog)");
  if (!animate) return start();

  const root = document.documentElement;
  root.dataset.adminTransition = kind;
  heldPatches = [];
  document
    .startViewTransition(() => {
      try {
        start();
      } finally {
        const held = heldPatches;
        heldPatches = null;
        held.forEach((patch) => patch());
      }
    })
    .finished.finally(() => delete root.dataset.adminTransition);
}
