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
  toggle.setAttribute("aria-expanded", getComputedStyle(body).display !== "none");
};

const syncCinderSortHeader = (th) => {
  if (th.querySelector(".hero-chevron-up")) th.setAttribute("aria-sort", "ascending");
  else if (th.querySelector(".hero-chevron-down")) th.setAttribute("aria-sort", "descending");
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
      node.querySelectorAll?.(`th, ${cinderControlSelector}`).forEach(makeCinderControlOperable);
    },
    onBeforeElUpdated(_from, to) {
      makeCinderControlOperable(to);
    },
  },
});

const scrollLockDialogSelector = ".js-scroll-lock-dialog";

const scrollLockDialogIsVisible = (dialog) => {
  if (
    !dialog.isConnected ||
    dialog.hidden ||
    dialog.getAttribute("aria-hidden") === "true"
  ) {
    return false;
  }

  const style = window.getComputedStyle(dialog);
  return style.display !== "none" && style.visibility !== "hidden";
};

const syncModalDialogScrollLock = () => {
  const anyVisibleDialog = Array.from(
    document.querySelectorAll(scrollLockDialogSelector),
  ).some(scrollLockDialogIsVisible);

  document.documentElement.classList.toggle(
    "overflow-hidden",
    anyVisibleDialog,
  );
};

// Other elements change styles every frame (e.g. carousel tweens), so only
// re-check when a drawer itself changed or nodes were added or removed.
// The same records keep Cinder's filter toggle in step with its panel, which
// JS.toggle shows and hides after a transition rather than on the click.
const modalDialogObserver = new MutationObserver((records) => {
  records.forEach(({ target }) => {
    if (!target.id?.endsWith("-filter-body")) return;

    const toggle = document.querySelector(`[aria-controls="${target.id}"]`);
    if (toggle) syncCinderFilterToggle(toggle);
  });

  if (
    records.some(
      (record) =>
        record.type === "childList" ||
        record.target.matches?.(scrollLockDialogSelector),
    )
  ) {
    syncModalDialogScrollLock();
  }
});

modalDialogObserver.observe(document.body, {
  subtree: true,
  childList: true,
  attributes: true,
  attributeFilter: ["class", "style", "hidden", "aria-hidden"],
});

window.addEventListener("phx:page-loading-stop", syncModalDialogScrollLock);
window.addEventListener("pageshow", syncModalDialogScrollLock);
syncModalDialogScrollLock();

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
