// @ts-check
import {
  elementReference,
  findHeexSource,
  selectorFor,
} from "./dev_element_reference.mjs";

// Option+Click on an element. In dev it copies page context and a
// source-mapped element reference. For reviewers (in dev or production) it
// also opens a box to leave a review note on the element. Touch screens have
// no Option key, so reviewers there get a button that toggles review mode,
// where a tap does what Option+Click does.
const dev = !!document.querySelector("[data-phx-loc]");
const reviewer = document.body.hasAttribute("data-reviewer");
const touch = matchMedia("(hover: none)").matches;
const admin = location.pathname.startsWith("/admin");

if ((dev || reviewer) && !admin) {
  let activeEl = null;
  let selection = 0;
  let lastTarget = null;
  let selectionPath = [];
  let copiedTimer = null;
  let overlay = null;
  let label = null;
  let hint = null;
  let box = null;
  let optionHeld = false;
  let notesPath = null;
  let notesRequest = null;
  let markers = [];
  let reviewMode = false;
  let toggle = null;
  let highlighted = null;

  const picking = (event) => event.altKey || reviewMode;
  const ours = (target) => box?.contains(target) || toggle?.contains(target);

  const clickHint = dev ? (reviewer ? "copy + note" : "copy") : "note";

  // The picker's own boxes are manual popovers in the top layer, placed with
  // CSS anchor positioning against the element they describe.
  const style = document.createElement("style");
  style.textContent = `
    .ep-highlight, .ep-label, .ep-box, .ep-note, .ep-toggle, .ep-intro {
      margin: 0;
      padding: 0;
      border: 0;
      inset: auto;
      overflow: visible;
      background: none;
      color: inherit;
    }
    .ep-highlight, .ep-note {
      pointer-events: none;
      /* Closed drawers have no anchor box; anchors-visible doesn't hide that case. */
      top: anchor(top, -10000px);
      left: anchor(left, -10000px);
      width: anchor-size(width);
      height: anchor-size(height);
      box-sizing: border-box;
      border-radius: 4px;
      position-visibility: anchors-visible;
    }
    .ep-highlight {
      border: 1.5px solid oklch(55% 0.16 155);
      background: oklch(55% 0.16 155 / 0.08);
    }
    .ep-highlight.ep-flash {
      border-color: oklch(65% 0.2 155);
      background: oklch(65% 0.2 155 / 0.18);
    }
    .ep-label {
      pointer-events: none;
      position-area: top span-right;
      position-try-fallbacks: flip-block, flip-inline, flip-block flip-inline;
      position-visibility: anchors-visible;
      margin-block: 4px;
      max-width: calc(100vw - 8px);
      padding: 3px 7px;
      background: oklch(22% 0.03 155);
      color: oklch(96% 0.01 155);
      font: 11px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
      border-radius: 4px;
      box-shadow: 0 2px 8px rgb(0 0 0 / 0.28);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .ep-label span {
      display: block;
      opacity: 0.65;
    }
    .ep-box:popover-open {
      display: grid;
    }
    .ep-box {
      position-area: bottom span-right;
      position-try-fallbacks: flip-block, flip-inline, flip-block flip-inline,
        --ep-viewport-corner;
      margin-block: 8px;
      width: 320px;
      box-sizing: border-box;
      padding: 10px;
      grid-template-columns: minmax(0, 1fr);
      gap: 8px;
      background: oklch(99% 0.005 155);
      color: oklch(22% 0.03 155);
      border: 1px solid oklch(55% 0.16 155);
      border-radius: 6px;
      box-shadow: 0 6px 24px rgb(0 0 0 / 0.22);
      font: 13px/1.4 system-ui, sans-serif;
    }
    /* A large element leaves no room beside it, so keep the box on screen. */
    @position-try --ep-viewport-corner {
      position-area: none;
      inset: auto 8px 8px auto;
      margin: 0;
    }
    /* A sheet along the bottom stays above the on-screen keyboard. */
    @media (hover: none) {
      .ep-box {
        position-area: none;
        position-try-fallbacks: none;
        inset: auto 8px calc(8px + var(--keyboard, 0px)) 8px;
        width: auto;
        margin: 0;
      }
    }
    .ep-note {
      border: 1.5px dashed oklch(70% 0.16 70);
    }
    .ep-note-text {
      position: absolute;
      top: 100%;
      left: 0;
      max-width: 260px;
      margin-top: 2px;
      padding: 2px 6px;
      background: oklch(92% 0.08 85);
      color: oklch(25% 0.05 70);
      font: 11px/1.4 system-ui, sans-serif;
      border-radius: 4px;
    }
    .ep-toggle {
      left: 16px;
      bottom: calc(16px + env(safe-area-inset-bottom));
      width: 44px;
      height: 44px;
      border: 1.5px solid oklch(55% 0.16 155);
      border-radius: 50%;
      background: oklch(99% 0.005 155);
      color: oklch(22% 0.03 155);
      font-size: 20px;
      box-shadow: 0 2px 8px rgb(0 0 0 / 0.28);
    }
    .ep-toggle[aria-pressed="true"] {
      background: oklch(55% 0.16 155);
      color: oklch(99% 0.005 155);
    }
    .ep-intro:popover-open {
      display: flex;
    }
    .ep-intro {
      left: 16px;
      bottom: 16px;
      align-items: center;
      gap: 4px;
      padding: 6px 4px 6px 12px;
      border: 1px solid oklch(55% 0.16 155);
      border-radius: 6px;
      background: oklch(99% 0.005 155);
      color: oklch(22% 0.03 155);
      box-shadow: 0 2px 8px rgb(0 0 0 / 0.28);
      font: 13px/1.4 system-ui, sans-serif;
    }
  `;
  document.head.append(style);

  const popover = (tag, className) => {
    const node = document.createElement(tag);
    node.popover = "manual";
    node.className = className;
    return node;
  };

  const show = (node, host) => {
    if (node.parentNode !== host) host.append(node);
    if (!node.matches(":popover-open")) node.showPopover();
  };

  const hide = (node) => {
    if (node?.matches(":popover-open")) node.hidePopover();
  };

  // Anchoring needs an anchor-name on the page's own element. Each element gets
  // one generated name, added beside any it already has and removed once the
  // last overlay on it closes. A LiveView patch rewrites the style attribute,
  // so the observer puts the name back.
  const anchors = new Map();
  let anchorCount = 0;

  const anchorNames = (el) =>
    getComputedStyle(el)
      .getPropertyValue("anchor-name")
      .split(",")
      .map((name) => name.trim())
      .filter((name) => name.startsWith("--"));

  const addAnchorName = (el, name) => {
    if (anchorNames(el).includes(name)) return;
    el.style.setProperty("anchor-name", [...anchorNames(el), name].join(", "));
  };

  const anchorTo = (el) => {
    let anchor = anchors.get(el);
    if (!anchor) {
      anchor = {
        name: `--element-picker-${++anchorCount}`,
        observer: new MutationObserver(() => addAnchorName(el, anchor.name)),
        users: 0,
      };
      anchors.set(el, anchor);
      addAnchorName(el, anchor.name);
      anchor.observer.observe(el, {
        attributes: true,
        attributeFilter: ["style"],
      });
    }
    anchor.users++;
    return anchor.name;
  };

  const releaseAnchor = (el) => {
    const anchor = anchors.get(el);
    if (!anchor || --anchor.users) return;
    anchors.delete(el);
    anchor.observer.disconnect();
    const names = el.style
      .getPropertyValue("anchor-name")
      .split(",")
      .map((name) => name.trim())
      .filter((name) => name && name !== anchor.name);
    if (names.length) el.style.setProperty("anchor-name", names.join(", "));
    else el.style.removeProperty("anchor-name");
  };

  const ensureOverlay = () => {
    if (overlay) return;
    overlay = popover("div", "ep-highlight");
    label = popover("div", "ep-label");
    hint = document.createElement("span");
  };

  const highlightAnchor = (el) => {
    if (highlighted === el) return;
    if (highlighted) releaseAnchor(highlighted);
    highlighted = el;
    const name = anchorTo(el);
    for (const node of [overlay, label])
      node.style.setProperty("position-anchor", name);
  };

  const pickTarget = (el) => el.closest("svg") || el;

  // A modal drawer makes everything outside it inert, and a site popover would
  // light-dismiss on a click in a box outside it, so join the open one.
  const hostFor = (el) =>
    el.closest(":popover-open, dialog:modal") || document.body;

  const tagSummary = (el) => {
    const tag = el.tagName.toLowerCase();
    if (el.id) return `${tag}#${el.id}`;
    const text = (el.getAttribute("aria-label") || el.textContent || "")
      .replace(/\s+/g, " ")
      .trim();
    const excerpt = text.length > 40 ? `${text.slice(0, 37)}...` : text;
    return excerpt ? `${tag} ${JSON.stringify(excerpt)}` : tag;
  };

  const shortFile = (path) => path?.split("/").pop() ?? "";

  const renderHighlight = (el, flashText = null) => {
    ensureOverlay();
    const host = hostFor(el);
    highlightAnchor(el);
    overlay.className = flashText ? "ep-highlight ep-flash" : "ep-highlight";
    show(overlay, host);

    // An open box covers the same spot, so the label would only peek out beneath it.
    if (box) return hide(label);

    const src = findHeexSource(el);
    const sourceLabel = src
      ? `${src.mappedElement !== el ? "~" : ""}${shortFile(src.file)}:${src.location.split(":").pop()}`
      : "no source";
    label.textContent = dev
      ? `${tagSummary(el)} · ${sourceLabel}`
      : tagSummary(el);
    hint.textContent =
      flashText || `⌥↑ parent · ⌥↓ child · ⌥click ${clickHint}`;
    label.append(hint);
    show(label, host);
  };

  const hideHighlight = () => {
    if (copiedTimer || box) return;
    activeEl = null;
    hide(overlay);
    hide(label);
    if (highlighted) releaseAnchor(highlighted);
    highlighted = null;
  };

  const flash = (el, message) => {
    clearTimeout(copiedTimer);
    renderHighlight(el, message);
    copiedTimer = setTimeout(() => {
      copiedTimer = null;
      hideHighlight();
    }, 900);
  };

  const keepAboveKeyboard = () => {
    const viewport = window.visualViewport;
    if (!box || !viewport) return;
    const keyboard = innerHeight - viewport.offsetTop - viewport.height;
    box.style.setProperty("--keyboard", `${Math.max(0, keyboard)}px`);
  };

  const closeBox = () => {
    selection++;
    if (box) releaseAnchor(activeEl);
    box?.remove();
    box = null;
    hideHighlight();
    if (reviewMode) showNotes();
  };

  const sendJson = (url, data, method = "POST") =>
    fetch(url, {
      method,
      headers: {
        "content-type": "application/json",
        "x-csrf-token": /** @type {HTMLMetaElement} */ (
          document.querySelector("meta[name='csrf-token']")
        ).content,
      },
      body: JSON.stringify(data),
    }).catch(() => null);

  const pagePath = () => location.pathname + location.search;

  // Everything a translated string could render as: the whole text, each text
  // node, and the attributes people read, such as a placeholder or alt text.
  const textsFor = (el) => {
    const texts = [el.innerText];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) texts.push(walker.currentNode.textContent);
    const attributes = ["placeholder", "alt", "aria-label", "title"];
    const labelled = el.querySelectorAll(
      attributes.map((name) => `[${name}]`).join(","),
    );
    for (const node of [el, ...labelled])
      for (const name of attributes) texts.push(node.getAttribute(name));
    const cleaned = texts
      .map((text) => text?.replace(/\s+/g, " ").trim())
      .filter(Boolean);
    return [...new Set(cleaned)].slice(0, 50);
  };

  const stringsList = (strings) => {
    const list = document.createElement("div");
    Object.assign(list.style, {
      display: "grid",
      maxHeight: "200px",
      overflowY: "auto",
      fontSize: "12px",
    });
    const locale = document.documentElement.lang.split("-")[0];
    strings.forEach((string, index) => {
      const entry = document.createElement("div");
      Object.assign(entry.style, {
        display: "grid",
        gridTemplateColumns: "auto 1fr",
        columnGap: "8px",
        rowGap: "2px",
        padding: "6px 0",
        borderTop: index ? "1px solid oklch(90% 0.01 155)" : "none",
      });
      // The page already shows its own language, so only the others to compare against.
      for (const other of ["en", "sv", "fi"]) {
        if (other === locale || !(other in string.translations)) continue;
        const code = document.createElement("span");
        code.textContent = other.toUpperCase();
        Object.assign(code.style, {
          fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
          fontSize: "10px",
          lineHeight: "18px",
          opacity: "0.5",
        });
        const text = document.createElement("span");
        text.textContent = string.translations[other] ?? "Not translated";
        if (string.translations[other] == null)
          Object.assign(text.style, { fontStyle: "italic", opacity: "0.5" });
        entry.append(code, text);
      }
      const where = document.createElement("span");
      where.textContent = [`${string.domain}.po`, string.msgctxt]
        .filter(Boolean)
        .join(" · ");
      Object.assign(where.style, {
        gridColumn: "2",
        fontSize: "10px",
        opacity: "0.45",
      });
      entry.append(where);
      list.append(entry);
    });
    return list;
  };

  const hideNotes = () => {
    for (const { marker, el } of markers) {
      marker.remove();
      releaseAnchor(el);
    }
    markers = [];
  };

  const noteElement = (note) => {
    try {
      return document.querySelector(note.selector);
    } catch {
      return null;
    }
  };

  const renderNotes = (notes) => {
    hideNotes();
    for (const note of notes) {
      const el = noteElement(note);
      if (!el) continue;

      const marker = popover("div", "ep-note");
      marker.style.setProperty("position-anchor", anchorTo(el));
      const text = document.createElement("div");
      text.className = "ep-note-text";
      text.textContent =
        note.body.length > 80 ? `${note.body.slice(0, 77)}...` : note.body;
      marker.append(text);
      show(marker, hostFor(el));
      markers.push({ marker, el });
    }
  };

  // Follow drawers into and out of the top layer as they open and close.
  document.addEventListener(
    "toggle",
    (event) => {
      for (const { marker, el } of markers) {
        if (event.target.contains(el)) show(marker, hostFor(el));
      }
    },
    true,
  );

  // Open notes for this page, fetched once per path.
  const pageNotes = () => {
    if (notesPath !== pagePath()) {
      notesPath = pagePath();
      notesRequest = fetch(
        `/review-notes?path=${encodeURIComponent(notesPath)}`,
      )
        .then((response) => (response.ok ? response.json() : []))
        .catch(() => []);
    }
    return notesRequest;
  };

  const showNotes = async () => {
    if (!reviewer) return;
    const path = pagePath();
    const request = pageNotes();
    const notes = await request;
    if (path !== pagePath() || request !== notesRequest) return;
    if ((optionHeld || reviewMode) && !box) renderNotes(notes);
  };

  // Option+Clicking an element again opens the reviewer's own note on it.
  const ownNoteOn = async (el) =>
    (await pageNotes()).find(
      (note) => note["mine?"] && noteElement(note) === el,
    );

  const noteContextFor = (el) => ({
    path: location.pathname + location.search,
    locale: document.documentElement.lang,
    viewport: `${innerWidth}x${innerHeight}`,
    selector: selectorFor(el).slice(0, 2000),
    element_text: el.innerText?.trim().replace(/\s+/g, " ").slice(0, 500),
    element_html: el.outerHTML.slice(0, 2000),
    source: findHeexSource(el)?.location,
  });

  const copyReference = async (el, body = "") => {
    try {
      const reference = elementReference(el, document);
      await navigator.clipboard.writeText(
        body.trim() ? `${reference}\n\n${body.trim()}` : reference,
      );
      return "✓ Copied";
    } catch (error) {
      console.error("Could not copy element reference", error);
      return "Could not copy — check clipboard permissions";
    }
  };

  const iconButton = (label, path) => {
    const button = document.createElement("button");
    button.type = "button";
    button.title = label;
    button.setAttribute("aria-label", label);
    button.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}" /></svg>`;
    Object.assign(button.style, {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      minWidth: touch ? "44px" : "36px",
      minHeight: touch ? "44px" : "36px",
    });
    return button;
  };

  const openBox = (el, heading, note = null) => {
    const noteContext = note ? null : noteContextFor(el);
    let saving = false;
    if (box) releaseAnchor(activeEl);
    box?.remove();
    activeEl = el;
    box = popover("form", "ep-box");
    const thisBox = box;
    const path = pagePath();
    hideNotes();
    renderHighlight(el);
    box.style.setProperty("position-anchor", anchorTo(el));

    const title = document.createElement("div");
    title.textContent = heading;
    Object.assign(title.style, {
      flex: "1",
      minWidth: "0",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      fontSize: "11px",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap",
    });

    const textarea = document.createElement("textarea");
    textarea.rows = 4;
    textarea.placeholder = "Write comment here";
    textarea.value = note?.body ?? "";
    textarea.setAttribute("aria-label", "Review note");
    Object.assign(textarea.style, {
      width: "100%",
      boxSizing: "border-box",
      padding: "6px",
      border: "1px solid oklch(80% 0.02 155)",
      borderRadius: "4px",
      font: "inherit",
      // iOS zooms into inputs with text under 16px.
      fontSize: touch ? "16px" : "inherit",
      resize: "vertical",
    });

    const status = document.createElement("span");
    status.textContent = touch
      ? ""
      : dev
        ? "⌘↵ to copy, ⌘S to save, Esc to cancel"
        : "⌘S to save, Esc to cancel";
    Object.assign(status.style, {
      fontSize: "11px",
      opacity: "0.7",
      textAlign: "right",
    });

    const save = iconButton(
      "Save",
      "M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h12l4 4v12a2 2 0 0 1-2 2Z M17 21v-8H7v8 M7 3v5h8V3",
    );
    save.type = "submit";
    const close = iconButton("Close", "M18 6 6 18 M6 6l12 12");
    close.addEventListener("click", closeBox);

    const actions = document.createElement("div");
    Object.assign(actions.style, {
      display: "flex",
      flexWrap: "wrap",
      justifyContent: "flex-end",
      gap: "10px",
      alignItems: "center",
    });
    // A reviewer may have copied text to paste into the note, so the reference
    // is copied only when asked for.
    const copy = iconButton("Copy ref", "M9 9h12v12H9z M5 15H3V3h12v2");
    const copyNoteReference = async () => {
      const message = await copyReference(el, textarea.value);
      if (box === thisBox && path === pagePath()) status.textContent = message;
    };
    copy.addEventListener("click", copyNoteReference);
    const remove = iconButton(
      "Delete",
      "M3 6h18 M9 6V3h6v3 M5 6l1 15h12l1-15 M10 10v7 M14 10v7",
    );
    remove.style.marginRight = "auto";
    remove.addEventListener("click", async () => {
      if (!confirm("Delete this note?")) return;
      status.textContent = "Deleting…";
      const response = await sendJson(`/review-notes/${note.id}`, {}, "DELETE");
      if (response?.ok) notesPath = null;
      if (box !== thisBox || path !== pagePath()) return;
      if (response?.ok) {
        closeBox();
        flash(el, "✓ Note deleted");
      } else {
        status.textContent = `Could not delete (${response?.status ?? "offline"}), try again`;
      }
    });
    actions.append(
      ...(note ? [remove] : []),
      ...(dev ? [copy] : []),
      close,
      save,
    );
    const strings = document.createElement("div");
    strings.textContent = "Looking up strings…";
    Object.assign(strings.style, { fontSize: "11px", opacity: "0.7" });
    box.append(title, strings, textarea, actions, status);

    const stringsRequest = sendJson("/review-notes/strings", {
      texts: textsFor(el),
      locale: document.documentElement.lang,
    })
      .then((response) => (response?.ok ? response.json() : []))
      .catch(() => []);

    stringsRequest.then((found) => {
      if (box !== thisBox || path !== pagePath()) return;
      if (found.length) strings.replaceWith(stringsList(found));
      else strings.textContent = "No translated strings found here";
    });

    // Keep the page's own shortcuts, like Escape closing a drawer, out of the box.
    box.addEventListener("keydown", (event) => {
      event.stopPropagation();
      if (event.key === "Escape") closeBox();
      if (
        event.key.toLowerCase() === "s" &&
        (event.metaKey || event.ctrlKey) &&
        !event.shiftKey
      ) {
        event.preventDefault();
        box.requestSubmit();
      }
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        if (dev) return copyNoteReference();
      }
    });

    box.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (saving) return;
      const body = textarea.value.trim();
      if (!body) return textarea.focus();

      saving = true;
      save.disabled = true;
      status.textContent = "Saving…";
      const response = note
        ? await sendJson(`/review-notes/${note.id}`, { body }, "PATCH")
        : await sendJson("/review-notes", {
            ...noteContext,
            body,
            strings: (await stringsRequest).map(
              ({ domain, msgctxt, msgid }) => ({
                domain,
                msgctxt,
                msgid,
              }),
            ),
          });

      if (response?.ok) notesPath = null;
      if (box !== thisBox || path !== pagePath()) return;
      if (response?.ok) {
        closeBox();
        flash(el, "✓ Note saved");
      } else {
        saving = false;
        save.disabled = false;
        status.textContent = `Could not save (${response?.status ?? "offline"}), try again`;
      }
    });

    show(box, hostFor(el));
    keepAboveKeyboard();
    textarea.focus();
  };

  const pick = async (el) => {
    const current = ++selection;
    const path = pagePath();
    const note = reviewer ? await ownNoteOn(el) : null;
    if (current !== selection || path !== pagePath()) return;
    const heading = note ? `Editing note · ${tagSummary(el)}` : tagSummary(el);
    if (reviewer) openBox(el, heading, note);
    else {
      const message = await copyReference(el);
      if (current === selection && path === pagePath()) flash(el, message);
    }
  };

  if (reviewer && touch) {
    toggle = popover("button", "ep-toggle");
    toggle.type = "button";
    toggle.textContent = "✎";
    toggle.setAttribute("aria-label", "Review mode");
    toggle.setAttribute("aria-pressed", "false");
    toggle.addEventListener("click", () => {
      reviewMode = !reviewMode;
      toggle.setAttribute("aria-pressed", String(reviewMode));
      if (reviewMode) return showNotes();
      closeBox();
      hideNotes();
    });
    show(toggle, document.body);
  }

  // Desktop reviewers see the shortcut once per session, until they close it or press Option.
  let intro = null;
  const dismissIntro = () => {
    if (!intro) return;
    intro.remove();
    intro = null;
    try {
      sessionStorage.setItem("review-intro-seen", "1");
    } catch {}
  };
  let introSeen = true;
  try {
    introSeen = !!sessionStorage.getItem("review-intro-seen");
  } catch {}
  if (reviewer && !touch && !introSeen) {
    intro = popover("div", "ep-intro");
    const name = document.body.dataset.reviewerName;
    intro.append(
      `${name ? `Hi ${name}! ` : ""}Hold Option (⌥) and click anything to leave a comment`,
    );
    const close = iconButton("Close", "M18 6 6 18 M6 6l12 12");
    close.addEventListener("click", dismissIntro);
    intro.append(close);
    show(intro, document.body);
  }

  document.addEventListener(
    "mousemove",
    (event) => {
      if (box) return;
      const target = pickTarget(event.target);
      const changed = lastTarget !== target;
      lastTarget = target;
      if (!event.altKey) return hideHighlight();
      if (copiedTimer) return;
      if (!changed && activeEl) return;
      selection++;
      selectionPath = [];
      activeEl = target;
      renderHighlight(activeEl);
    },
    { passive: true },
  );

  document.addEventListener(
    "keydown",
    (event) => {
      // Option types characters such as å, so leave keys alone while writing a note.
      if (copiedTimer || box) return;
      if (event.key === "Alt" && !optionHeld) {
        optionHeld = true;
        dismissIntro();
        showNotes();
      }
      if (event.key === "Alt" && !activeEl && lastTarget) {
        selectionPath = [];
        activeEl = lastTarget;
        renderHighlight(activeEl);
      }
      if (!event.altKey || !activeEl) return;
      if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
      event.preventDefault();
      event.stopPropagation();
      selection++;
      if (event.key === "ArrowUp" && activeEl.parentElement) {
        selectionPath.push(activeEl);
        activeEl = activeEl.parentElement;
      } else if (event.key === "ArrowDown" && selectionPath.length) {
        activeEl = selectionPath.pop();
      }
      renderHighlight(activeEl);
    },
    true,
  );

  document.addEventListener("keyup", (event) => {
    if (event.key !== "Alt") return;
    optionHeld = false;
    hideNotes();
    hideHighlight();
  });

  window.addEventListener("blur", () => {
    optionHeld = false;
    if (reviewMode) return;
    hideNotes();
    hideHighlight();
  });
  window.visualViewport?.addEventListener("resize", keepAboveKeyboard);
  window.visualViewport?.addEventListener("scroll", keepAboveKeyboard);

  const stopAltPointer = (event) => {
    if (!picking(event) || ours(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
  };

  document.addEventListener("mousedown", stopAltPointer, true);
  document.addEventListener("pointerdown", stopAltPointer, true);
  // Option+Click elsewhere opens a new box instead, through the click handler.
  document.addEventListener(
    "pointerdown",
    (event) => {
      if (box && !picking(event) && !box.contains(event.target)) closeBox();
    },
    true,
  );

  document.addEventListener(
    "click",
    async (event) => {
      if (!picking(event) || ours(event.target)) return;
      const target = pickTarget(event.target);
      const kept = target === lastTarget && activeEl?.isConnected;
      const el = kept ? activeEl : target;
      if (!kept) selectionPath = [];

      event.preventDefault();
      event.stopPropagation();
      await pick(el);
    },
    true,
  );
}
