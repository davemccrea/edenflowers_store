// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

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

// View Transitions API integration.
//
// Elements opt in via `data-vt-name="<name>"`. A capture-phase click listener
// stamps `view-transition-name` on the element synchronously so the browser
// has the name in place when LiveView's link handler initiates navigation.
//
// We can't use `phx-click` + `JS.dispatch` here because LV's link click
// handler shadows `phx-click` on descendants of `<.link navigate>` — the
// navigation fires but the dispatch silently doesn't.
//
// onDocumentPatch wraps LV's DOM patch in `document.startViewTransition()`
// only when something has opted in; otherwise the patch runs normally with
// zero overhead. Fallback path covers Firefox <=144 (no callbackOptions).
let transitionTags = [];
let scheduleTransition = false;

document.addEventListener(
  "click",
  (e) => {
    const el =
      e.target instanceof Element
        ? e.target.closest("[data-vt-name]")
        : null;
    if (!el) return;
    const name = el.getAttribute("data-vt-name");
    if (!name) return;
    el.style.viewTransitionName = name;
    transitionTags.push(el);
    scheduleTransition = true;
  },
  { capture: true }
);

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...Hooks, ...colocatedHooks },
  dom: {
    onDocumentPatch(start) {
      const update = () => {
        transitionTags.forEach((el) => (el.style.viewTransitionName = ""));
        transitionTags = [];
        scheduleTransition = false;
        start();
      };

      if (!scheduleTransition || !document.startViewTransition) {
        update();
        return;
      }

      try {
        document.startViewTransition({ update });
      } catch (_err) {
        document.startViewTransition(update);
      }
    },
  },
});

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "oklch(36.84% 0.0478 156.76)" },
  shadowColor: "rgba(0, 0, 0, .3)",
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

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
// if (process.env.NODE_ENV === "development") {
//   window.addEventListener(
//     "phx:live_reload:attached",
//     ({ detail: reloader }) => {
//       // Enable server log streaming to client.
//       // Disable with reloader.disableServerLogs()
//       reloader.enableServerLogs();

//       // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
//       //
//       //   * click with "c" key pressed to open at caller location
//       //   * click with "d" key pressed to open at function component definition location
//       let keyDown;
//       window.addEventListener("keydown", (e) => (keyDown = e.key));
//       window.addEventListener("keyup", (_e) => (keyDown = null));
//       window.addEventListener(
//         "click",
//         (e) => {
//           if (keyDown === "c") {
//             e.preventDefault();
//             e.stopImmediatePropagation();
//             reloader.openEditorAtCaller(e.target);
//           } else if (keyDown === "d") {
//             e.preventDefault();
//             e.stopImmediatePropagation();
//             reloader.openEditorAtDef(e.target);
//           }
//         },
//         true
//       );

//       window.liveReloader = reloader;
//     }
//   );
// }
