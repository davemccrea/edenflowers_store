import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { hooks as colocatedHooks } from "phoenix-colocated/edenflowers";
import { hooks as cinderHooks } from "phoenix-colocated/cinder";
import liveSelect from "live_select";
import { customerLiveSelect } from "./customer_select";
import { VoucherCode } from "./voucher_code.mjs";
import { VoucherPreview } from "./voucher_preview.mjs";
import { cinderDom } from "./cinder_a11y";
import { onDocumentPatch } from "./page_transitions";
import "./unsaved_forms";

// Customers never use the picker, so only dev and reviewer pages fetch it.
if (
  document.querySelector("[data-phx-loc]") ||
  document.body.hasAttribute("data-reviewer")
) {
  import("./element_picker");
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // Waking a backgrounded tab drops the socket briefly; only toast if reconnecting drags on.
  disconnectedTimeout: 3000,
  params: { _csrf_token: csrfToken },
  hooks: {
    ...cinderHooks,
    ...colocatedHooks,
    ...liveSelect,
    LiveSelect: customerLiveSelect,
    VoucherCode,
    VoucherPreview,
  },
  dom: {
    onDocumentPatch,
    ...cinderDom,
  },
});

// Runs the JS command stored in an element's attribute, so the server can open
// the cart drawer only once an add has succeeded.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document
    .querySelectorAll(detail.to)
    .forEach((el) => liveSocket.execJS(el, el.getAttribute(detail.attr)));
});

// Navigating to the page already open keeps its scroll, so a fresh start asks for the top.
window.addEventListener("phx:scroll-top", () => window.scrollTo(0, 0));

window.addEventListener("phx:order-ready", () => {
  if (!document.querySelector(".admin-theme")) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  import("../vendor/canvas-confetti.mjs")
    .then(({ default: confetti }) =>
      confetti({
        particleCount: 70,
        spread: 70,
        origin: { y: 0.65 },
        ticks: 120,
        disableForReducedMotion: true,
      }),
    )
    .catch((error) =>
      console.error("Could not launch order-ready confetti", error),
    );
});

window.addEventListener("phx:order-fulfilled", () => {
  if (!document.querySelector(".admin-theme")) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  import("./fulfilledCelebration.js")
    .then(({ celebrateFulfilled }) => celebrateFulfilled())
    .catch((error) =>
      console.error("Could not launch order-fulfilled celebration", error),
    );
});

// Custom Umami events from EdenflowersWeb.Analytics. A `once` key is only
// remembered once Umami has it, so a blocked tracker doesn't eat the event.
window.addEventListener("phx:umami", ({ detail: { name, data, once } }) => {
  if (!window.umami) return;
  const key = once && `umami:${once}`;
  try {
    if (key && localStorage.getItem(key)) return;
    if (key) localStorage.setItem(key, "1");
  } catch {}
  window.umami.track(name, data);
});

topbar.config({
  shadowColor: "rgba(0, 0, 0, .3)",
});

// The bar runs over the storefront's pale header but over admin's dark chrome,
// so each names its colour in CSS (--color-loading-bar). Read it when the bar
// starts: an admin's colour choice, previewed live by the picker, applies then.
function showLoadingBar() {
  const color = getComputedStyle(document.body)
    .getPropertyValue("--color-loading-bar")
    .trim();
  if (color) topbar.config({ barColors: { 0: color } });
  topbar.show(300);
}

// The first connect happens behind an already-rendered page, so the bar would only flicker.
window.addEventListener("phx:page-loading-start", ({ detail }) => {
  if (detail.kind !== "initial") showLoadingBar();
});
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
