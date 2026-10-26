import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import { hooks as colocatedHooks } from "phoenix-colocated/edenflowers";
import liveSelect from "live_select";
import { customerLiveSelect } from "./customer_select";
import { cinderDom } from "./cinder_a11y";
import { onDocumentPatch } from "./admin_transitions";
import "./unsaved_forms";
import "./dev_element_picker";
import { loadStripe } from "./stripe";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // Waking a backgrounded tab drops the socket briefly; only toast if reconnecting drags on.
  disconnectedTimeout: 3000,
  params: { _csrf_token: csrfToken },
  hooks: {
    ...colocatedHooks,
    ...liveSelect,
    LiveSelect: customerLiveSelect,
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

topbar.config({
  barColors: { 0: "oklch(36.84% 0.0478 156.76)" },
  shadowColor: "rgba(0, 0, 0, .3)",
});

// The first connect happens behind an already-rendered page, so the bar would only flicker.
window.addEventListener("phx:page-loading-start", ({ detail }) => {
  if (detail.kind !== "initial") topbar.show(300);
});
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();

// After the hero image and LiveView, so Stripe.js never competes with them.
window.addEventListener("load", () => {
  const whenIdle =
    window.requestIdleCallback ?? ((callback) => setTimeout(callback));
  whenIdle(() => loadStripe().catch(() => {}), { timeout: 2000 });
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
