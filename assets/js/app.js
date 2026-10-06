// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
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

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...Hooks, ...colocatedHooks },
  dom: {
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

// The drawer component's phx-show/phx-hide dispatch these to its <dialog>.
window.addEventListener("drawer:open", (event) => event.target.showModal());
window.addEventListener("drawer:close", (event) => event.target.close());

// A tap on a drawer's ::backdrop reports the <dialog> itself as the target,
// since its content fills the rest of the box. closedby="any" would replace
// this once Safari supports it.
document.addEventListener("click", (event) => {
  if (event.target.matches?.("dialog.slide-drawer")) event.target.close();
});

// Show progress bar on live navigation and form submits
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

window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
