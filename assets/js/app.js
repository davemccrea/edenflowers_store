import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import Hooks from "./hooks";
import { hooks as colocatedHooks } from "phoenix-colocated/edenflowers";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
// Cinder renders its sort headers and filter-panel toggle as clickable divs and
// spans, which a keyboard can't reach. Its markup isn't themeable, so we give
// those elements button semantics as LiveView patches them in.
const cinderSortSelector = '[phx-click="toggle_sort"]';
const cinderFilterToggleSelector = '[data-key="filter_title_class"][phx-click]';
const cinderControlSelector = `${cinderSortSelector}, ${cinderFilterToggleSelector}`;

const syncCinderFilterToggle = (toggle) => {
  // During a patch the toggle sits in LiveView's detached copy, which has no
  // computed styles, so read the panel's visibility from the live document.
  const panelId = toggle
    .closest('[data-key="controls_class"]')
    ?.querySelector("[id$='-filter-body']")?.id;
  const body = panelId && document.getElementById(panelId);
  if (!body) return;

  toggle.setAttribute("aria-controls", body.id);
  toggle.setAttribute(
    "aria-expanded",
    getComputedStyle(body).display !== "none",
  );
};

const syncCinderSortHeader = (th) => {
  if (th.querySelector(".hero-chevron-up"))
    th.setAttribute("aria-sort", "ascending");
  else if (th.querySelector(".hero-chevron-down"))
    th.setAttribute("aria-sort", "descending");
  else th.removeAttribute("aria-sort");
};

const makeCinderControlOperable = (el) => {
  if (!(el instanceof HTMLElement)) return;

  if (el.tagName === "TH" && el.querySelector(cinderSortSelector)) {
    syncCinderSortHeader(el);
    return;
  }

  if (!el.matches(cinderControlSelector)) return;

  el.setAttribute("role", "button");
  el.setAttribute("tabindex", "0");
  if (el.matches(cinderFilterToggleSelector)) syncCinderFilterToggle(el);
};

document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  if (!event.target.matches?.(cinderControlSelector)) return;

  event.preventDefault();
  event.target.click();
});

// Admin forms marked data-warn-unsaved (holding the warning text) ask before a
// link leaves them with edits. Kept in a WeakSet rather than an attribute, which
// LiveView would strip on the next patch. A save navigates from the server, so
// it never asks; a failed save stays flagged.
const editedForms = new WeakSet();

const warnedForm = (el) =>
  el?.closest?.("form[data-warn-unsaved]") ||
  (el?.form?.matches("[data-warn-unsaved]") ? el.form : null);

const unsavedForm = () =>
  [...document.querySelectorAll("form[data-warn-unsaved]")].find((form) =>
    editedForms.has(form),
  );

document.addEventListener("input", (event) => {
  const form = warnedForm(event.target);
  if (form) editedForms.add(form);
});

// Adding or removing a size, translating and the like change the form on the
// server. A phx-click holding JS commands (copying a code) is client-only.
document.addEventListener("click", (event) => {
  const button = event.target.closest?.('button[type="button"][phx-click]');
  if (button?.getAttribute("phx-click").startsWith("[")) return;
  const form = warnedForm(button);
  if (form) editedForms.add(form);
});

window.addEventListener("phx:before-navigate", (event) => {
  const form = unsavedForm();
  if (!form) return;
  if (confirm(form.dataset.warnUnsaved)) return editedForms.delete(form);

  event.preventDefault();
});

window.addEventListener("beforeunload", (event) => {
  if (unsavedForm()) event.preventDefault();
});

window.addEventListener("phx:admin-form-saved", ({ detail }) => {
  const form = document.getElementById(detail.id);
  if (form) editedForms.delete(form);
});

document.addEventListener("keydown", (event) => {
  const typing = event.target.closest?.(
    "input, textarea, select, [contenteditable]",
  );
  const modified = event.metaKey || event.ctrlKey || event.altKey;

  if (event.key === "/" && !typing && !modified) {
    const search = [...document.querySelectorAll("[data-admin-search]")].find(
      (el) => el.offsetParent,
    );
    if (!search) return;
    event.preventDefault();
    search.focus();
  }
});

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
function onDocumentPatch(start) {
  if (heldPatches) return heldPatches.push(start);

  const kind = pendingAdminTransition;
  pendingAdminTransition = null;

  // An open drawer or modal would be snapshotted mid-page, so those navigations
  // swap instantly, as they did before.
  // Only the installed app animates, as a native one would. In a browser tab
  // pages swap straight away, as on most web apps.
  const animate =
    kind &&
    document.startViewTransition &&
    document.querySelector(".admin-theme") &&
    matchMedia("(display-mode: standalone)").matches &&
    !document.querySelector("dialog[open]");
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

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // Waking a backgrounded tab drops the socket briefly; only toast if reconnecting drags on.
  disconnectedTimeout: 3000,
  params: { _csrf_token: csrfToken },
  hooks: { ...Hooks, ...colocatedHooks },
  dom: {
    onDocumentPatch,
    onNodeAdded(node) {
      makeCinderControlOperable(node);
      node
        .querySelectorAll?.(`th, ${cinderControlSelector}`)
        .forEach(makeCinderControlOperable);
    },
    onBeforeElUpdated(_from, to) {
      makeCinderControlOperable(to);
    },
  },
});

// Keeps Cinder's filter toggle in step with its panel, which JS.toggle shows
// and hides after a transition rather than on the click.
const cinderFilterObserver = new MutationObserver((records) => {
  records.forEach(({ target }) => {
    if (!target.id?.endsWith("-filter-body")) return;

    const toggle = document.querySelector(`[aria-controls="${target.id}"]`);
    if (toggle) syncCinderFilterToggle(toggle);
  });
});

cinderFilterObserver.observe(document.body, {
  subtree: true,
  attributes: true,
  attributeFilter: ["class", "style"],
});

// Runs the JS command stored in an element's attribute, so the server can open
// the cart drawer only once an add has succeeded.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document
    .querySelectorAll(detail.to)
    .forEach((el) => liveSocket.execJS(el, el.getAttribute(detail.attr)));
});

// Slides a drawer out before closing it. Closing first and animating the exit
// needs `overlay` transitions, which WebKit lacks: Safari pulls the dialog out
// of the top layer at once and it vanishes instead of sliding.
async function closeDrawer(dialog) {
  if (!dialog.open) return;

  dialog.dataset.closing = "";
  await Promise.allSettled(dialog.getAnimations().map((a) => a.finished));

  // A reopen during the slide-out clears the flag and keeps it open.
  if (!("closing" in dialog.dataset)) return;
  delete dialog.dataset.closing;
  dialog.close();
}

function openDrawer(dialog) {
  delete dialog.dataset.closing;
  if (!dialog.open) dialog.showModal();
}

// The drawer component's phx-show/phx-hide dispatch these to its <dialog>.
window.addEventListener("drawer:open", (event) => openDrawer(event.target));
window.addEventListener("drawer:close", (event) => closeDrawer(event.target));

document.addEventListener(
  "cancel",
  (event) => {
    if (!event.target.matches("dialog.slide-drawer")) return;
    event.preventDefault();
    closeDrawer(event.target);
  },
  true,
);

// A tap on a drawer's ::backdrop reports the <dialog> itself as the target,
// since its content fills the rest of the box. closedby="any" would replace
// this once Safari supports it.
document.addEventListener("click", (event) => {
  if (event.target.matches?.("dialog.slide-drawer")) closeDrawer(event.target);
});

// Dragging a drawer back toward its edge closes it once it passes a third of
// its width or is flicked. Vertical drags stay scrolls (touch-action in layout.css).
document.addEventListener("pointerdown", (down) => {
  if (down.pointerType === "mouse") return;
  const dialog = down.target.closest?.("dialog.slide-drawer");
  if (!dialog?.open) return;

  const direction = dialog.classList.contains("slide-drawer--left") ? -1 : 1;
  let offset = 0;
  const listening = new AbortController();

  const move = (event) => {
    if (event.pointerId !== down.pointerId) return;
    offset = Math.max(0, (event.clientX - down.clientX) * direction);
    dialog.style.transition = "none";
    dialog.style.translate = `${offset * direction}px 0`;
  };

  const end = (event) => {
    if (event.pointerId !== down.pointerId) return;
    listening.abort();

    const velocity = offset / (event.timeStamp - down.timeStamp);
    const swiped = offset > dialog.offsetWidth / 3 || velocity > 0.5;

    // Clearing both in one go lets the CSS transition carry the drawer from
    // where the finger left it, either out or back into place.
    dialog.style.removeProperty("transition");
    dialog.style.removeProperty("translate");
    if (event.type === "pointerup" && swiped) closeDrawer(dialog);
  };

  const options = { signal: listening.signal };
  window.addEventListener("pointermove", move, options);
  window.addEventListener("pointerup", end, options);
  window.addEventListener("pointercancel", end, options);
});

// In the installed admin app, swiping right pulls the navigation drawer out
// under the finger, and lets go the same way as the swipe-to-close. The left
// edge is left to the iOS swipe back, and text fields to selecting text.
document.addEventListener("pointerdown", (down) => {
  if (down.pointerType === "mouse" || down.clientX < 20) return;
  if (!matchMedia("(display-mode: standalone)").matches) return;
  if (down.target.closest?.("input, textarea, select, [contenteditable]"))
    return;
  const dialog = document.getElementById("admin-nav-drawer-dialog");
  if (!dialog || document.querySelector("dialog[open]")) return;

  let offset = 0;
  const listening = new AbortController();

  const move = (event) => {
    if (event.pointerId !== down.pointerId) return;
    const dx = event.clientX - down.clientX;
    const dy = event.clientY - down.clientY;

    if (!dialog.open) {
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) return;
      // A mostly vertical drag is a scroll.
      if (dx <= Math.abs(dy)) return listening.abort();
      dialog.style.transition = "none";
      openDrawer(dialog);
    }

    offset = Math.min(Math.max(dx, 0), dialog.offsetWidth);
    dialog.style.translate = `${offset - dialog.offsetWidth}px 0`;
  };

  const end = (event) => {
    if (event.pointerId !== down.pointerId) return;
    listening.abort();
    if (!dialog.open) return;

    const velocity = offset / (event.timeStamp - down.timeStamp);
    const swiped = offset > dialog.offsetWidth / 3 || velocity > 0.5;

    dialog.style.removeProperty("transition");
    dialog.style.removeProperty("translate");
    if (event.type !== "pointerup" || !swiped) closeDrawer(dialog);
  };

  const options = { signal: listening.signal };
  window.addEventListener("pointermove", move, options);
  window.addEventListener("pointerup", end, options);
  window.addEventListener("pointercancel", end, options);
});

topbar.config({
  barColors: { 0: "oklch(36.84% 0.0478 156.76)" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
// detail.trigger names the button to mark data-copied for a moment, so it can
// show (and, inside an aria-live region, announce) that the copy worked.
window.addEventListener("edenflowers:copy", async (event) => {
  const el = event.target;
  const text = "value" in el ? el.value : el.textContent.trim();
  // Needs a secure page (HTTPS or localhost); plain http has no Clipboard API.
  const copied = await navigator.clipboard
    ?.writeText(text)
    .then(() => true)
    .catch(() => false);

  const trigger =
    event.detail?.trigger && document.querySelector(event.detail.trigger);
  if (!copied || !trigger) return;

  trigger.dataset.copied = "";
  clearTimeout(trigger.copiedTimer);
  trigger.copiedTimer = setTimeout(() => delete trigger.dataset.copied, 2000);
});

// The first connect happens behind an already-rendered page, so the bar would only flicker.
window.addEventListener("phx:page-loading-start", ({ detail }) => {
  if (detail.kind !== "initial") topbar.show(300);
});
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
