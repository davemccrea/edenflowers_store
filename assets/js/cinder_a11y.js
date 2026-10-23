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

export const cinderDom = {
  onNodeAdded(node) {
    makeCinderControlOperable(node);
    node
      .querySelectorAll?.(`th, ${cinderControlSelector}`)
      .forEach(makeCinderControlOperable);
  },
  onBeforeElUpdated(_from, to) {
    makeCinderControlOperable(to);
  },
};
