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

if (dev || reviewer) {
  let activeEl = null;
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

  const picking = (event) => event.altKey || reviewMode;
  const ours = (target) => box?.contains(target) || toggle?.contains(target);

  const clickHint = dev ? (reviewer ? "copy + note" : "copy") : "note";

  const ensureOverlay = () => {
    if (overlay) return;
    overlay = document.createElement("div");
    Object.assign(overlay.style, {
      position: "fixed",
      pointerEvents: "none",
      zIndex: "2147483647",
      border: "1.5px solid oklch(55% 0.16 155)",
      background: "oklch(55% 0.16 155 / 0.08)",
      borderRadius: "4px",
      transition: "all 60ms ease-out",
      display: "none",
    });

    label = document.createElement("div");
    Object.assign(label.style, {
      position: "fixed",
      pointerEvents: "none",
      zIndex: "2147483647",
      background: "oklch(22% 0.03 155)",
      color: "oklch(96% 0.01 155)",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      fontSize: "11px",
      lineHeight: "1.4",
      padding: "3px 7px",
      borderRadius: "4px",
      boxShadow: "0 2px 8px rgba(0,0,0,0.28)",
      whiteSpace: "nowrap",
      maxWidth: "calc(100vw - 8px)",
      overflow: "hidden",
      textOverflow: "ellipsis",
      display: "none",
    });
    hint = document.createElement("span");
    Object.assign(hint.style, { display: "block", opacity: "0.65" });

    document.body.append(overlay, label);
  };

  const pickTarget = (el) => el.closest("svg") || el;

  // Modal drawers sit in the browser's top layer, above every body z-index.
  // Keep the picker in the same layer as the element being inspected.
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
    if (overlay.parentNode !== host) host.append(overlay, label);

    const rect = el.getBoundingClientRect();
    Object.assign(overlay.style, {
      display: "block",
      top: `${rect.top}px`,
      left: `${rect.left}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
      borderColor: flashText ? "oklch(65% 0.2 155)" : "oklch(55% 0.16 155)",
      background: flashText
        ? "oklch(65% 0.2 155 / 0.18)"
        : "oklch(55% 0.16 155 / 0.08)",
    });

    // An open box covers the same spot, so the label would only peek out beneath it.
    if (box) {
      label.style.display = "none";
      return;
    }

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
    label.style.display = "block";

    const size = label.getBoundingClientRect();
    const top =
      rect.top > size.height + 8
        ? rect.top - size.height - 4
        : Math.max(4, Math.min(rect.bottom + 4, innerHeight - size.height - 4));
    const left = Math.max(4, Math.min(rect.left, innerWidth - size.width - 4));
    Object.assign(label.style, {
      display: "block",
      top: `${top}px`,
      left: `${left}px`,
    });
  };

  const hideHighlight = () => {
    if (copiedTimer || box) return;
    activeEl = null;
    if (overlay) overlay.style.display = "none";
    if (label) label.style.display = "none";
  };

  const flash = (el, message) => {
    clearTimeout(copiedTimer);
    renderHighlight(el, message);
    copiedTimer = setTimeout(() => {
      copiedTimer = null;
      hideHighlight();
    }, 900);
  };

  const positionBox = () => {
    // A sheet along the bottom of the visual viewport stays above the on-screen keyboard.
    if (touch) {
      const viewport = window.visualViewport;
      const bottom = viewport
        ? viewport.offsetTop + viewport.height
        : innerHeight;
      Object.assign(box.style, {
        top: `${bottom - box.offsetHeight - 8}px`,
        left: "8px",
      });
      return;
    }
    const rect = activeEl.getBoundingClientRect();
    const height = box.offsetHeight;
    const below = rect.bottom + 8;
    const top =
      below + height < innerHeight
        ? below
        : Math.max(
            8,
            Math.min(rect.top - height - 8, innerHeight - height - 8),
          );
    const left = Math.max(
      8,
      Math.min(rect.left, innerWidth - box.offsetWidth - 8),
    );
    Object.assign(box.style, { top: `${top}px`, left: `${left}px` });
  };

  const closeBox = () => {
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
    for (const marker of markers) marker.remove();
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

      const rect = el.getBoundingClientRect();
      const marker = document.createElement("div");
      Object.assign(marker.style, {
        position: "fixed",
        pointerEvents: "none",
        zIndex: "2147483646",
        top: `${rect.top}px`,
        left: `${rect.left}px`,
        width: `${rect.width}px`,
        height: `${rect.height}px`,
        border: "1.5px dashed oklch(70% 0.16 70)",
        borderRadius: "4px",
      });
      const text = document.createElement("div");
      text.textContent =
        note.body.length > 80 ? `${note.body.slice(0, 77)}...` : note.body;
      Object.assign(text.style, {
        position: "absolute",
        top: "100%",
        left: "0",
        maxWidth: "260px",
        marginTop: "2px",
        padding: "2px 6px",
        background: "oklch(92% 0.08 85)",
        color: "oklch(25% 0.05 70)",
        font: "11px/1.4 system-ui, sans-serif",
        borderRadius: "4px",
      });
      marker.append(text);
      hostFor(el).append(marker);
      markers.push(marker);
    }
  };

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
    const notes = await pageNotes();
    if ((optionHeld || reviewMode) && !box) renderNotes(notes);
  };

  // Option+Clicking an element again opens the reviewer's own note on it.
  const ownNoteOn = async (el) =>
    (await pageNotes()).find(
      (note) => note["mine?"] && noteElement(note) === el,
    );

  const noteFor = (el, body, strings) => ({
    body,
    path: location.pathname + location.search,
    locale: document.documentElement.lang,
    viewport: `${innerWidth}x${innerHeight}`,
    selector: selectorFor(el).slice(0, 2000),
    element_text: el.innerText?.trim().replace(/\s+/g, " ").slice(0, 500),
    element_html: el.outerHTML.slice(0, 2000),
    source: findHeexSource(el)?.location,
    strings: strings.map(({ domain, msgctxt, msgid }) => ({
      domain,
      msgctxt,
      msgid,
    })),
  });

  const copyReference = async (el) => {
    try {
      await navigator.clipboard.writeText(elementReference(el, document));
      return "✓ Copied";
    } catch (error) {
      console.error("Could not copy element reference", error);
      return "Could not copy — check clipboard permissions";
    }
  };

  const openBox = (el, heading, note = null) => {
    box?.remove();
    activeEl = el;
    box = document.createElement("form");
    hideNotes();
    renderHighlight(el);

    Object.assign(box.style, {
      position: "fixed",
      zIndex: "2147483647",
      width: touch ? "calc(100vw - 16px)" : "320px",
      boxSizing: "border-box",
      padding: "10px",
      display: "grid",
      gridTemplateColumns: "minmax(0, 1fr)",
      gap: "8px",
      background: "oklch(99% 0.005 155)",
      color: "oklch(22% 0.03 155)",
      border: "1px solid oklch(55% 0.16 155)",
      borderRadius: "6px",
      boxShadow: "0 6px 24px rgba(0,0,0,0.22)",
      font: "13px/1.4 system-ui, sans-serif",
    });

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

    // The buttons version of Option+↑ and Option+↓, for touch screens.
    const larger = document.createElement("button");
    larger.type = "button";
    larger.textContent = "Larger";
    larger.disabled = !el.parentElement || el.parentElement === document.body;
    larger.addEventListener("click", () => {
      selectionPath.push(el);
      pick(el.parentElement);
    });

    const smaller = document.createElement("button");
    smaller.type = "button";
    smaller.textContent = "Smaller";
    smaller.disabled = !selectionPath.length;
    smaller.addEventListener("click", () => pick(selectionPath.pop()));

    const header = document.createElement("div");
    Object.assign(header.style, {
      display: "flex",
      gap: "10px",
      alignItems: "center",
    });
    header.append(title, larger, smaller);

    const textarea = document.createElement("textarea");
    textarea.rows = 4;
    textarea.placeholder = "What should change here?";
    textarea.value = note?.body ?? "";
    textarea.setAttribute("aria-label", "Review note");
    Object.assign(textarea.style, {
      width: "100%",
      padding: "6px",
      border: "1px solid oklch(80% 0.02 155)",
      borderRadius: "4px",
      font: "inherit",
      // iOS zooms into inputs with text under 16px.
      fontSize: touch ? "16px" : "inherit",
      resize: "vertical",
    });

    const status = document.createElement("span");
    status.textContent = touch ? "" : "⌘↵ to save, Esc to cancel";
    Object.assign(status.style, {
      flex: "1",
      fontSize: "11px",
      opacity: "0.7",
    });

    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.textContent = "Cancel";
    cancel.addEventListener("click", closeBox);

    const save = document.createElement("button");
    save.type = "submit";
    save.textContent = "Save";
    Object.assign(save.style, { fontWeight: "600" });

    const actions = document.createElement("div");
    Object.assign(actions.style, {
      display: "flex",
      gap: "10px",
      alignItems: "center",
    });
    // A reviewer may have copied text to paste into the note, so the reference
    // is copied only when asked for.
    const copy = document.createElement("button");
    copy.type = "button";
    copy.textContent = "Copy ref";
    copy.addEventListener("click", async () => {
      status.textContent = await copyReference(el);
    });
    actions.append(status, ...(dev ? [copy] : []), cancel, save);
    const strings = document.createElement("div");
    strings.textContent = "Looking up strings…";
    Object.assign(strings.style, { fontSize: "11px", opacity: "0.7" });
    box.append(header, strings, textarea, actions);

    const stringsRequest = sendJson("/review-notes/strings", {
      texts: textsFor(el),
      locale: document.documentElement.lang,
    })
      .then((response) => (response?.ok ? response.json() : []))
      .catch(() => []);

    stringsRequest.then((found) => {
      if (found.length) strings.replaceWith(stringsList(found));
      else strings.textContent = "No translated strings found here";
      if (box) positionBox();
    });

    // Keep the page's own shortcuts, like Escape closing a drawer, out of the box.
    box.addEventListener("keydown", (event) => {
      event.stopPropagation();
      if (event.key === "Escape") closeBox();
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        box.requestSubmit();
      }
    });

    box.addEventListener("submit", async (event) => {
      event.preventDefault();
      const body = textarea.value.trim();
      if (!body) return textarea.focus();

      save.disabled = true;
      status.textContent = "Saving…";
      const response = note
        ? await sendJson(`/review-notes/${note.id}`, { body }, "PATCH")
        : await sendJson(
            "/review-notes",
            noteFor(el, body, await stringsRequest),
          );

      if (response?.ok) {
        notesPath = null;
        closeBox();
        flash(el, "✓ Note saved");
      } else {
        save.disabled = false;
        status.textContent = `Could not save (${response?.status ?? "offline"}), try again`;
      }
    });

    hostFor(el).append(box);
    positionBox();
    textarea.focus();
  };

  const pick = async (el) => {
    const note = reviewer ? await ownNoteOn(el) : null;
    const heading = note ? `Editing note · ${tagSummary(el)}` : tagSummary(el);
    if (reviewer) openBox(el, heading, note);
    else flash(el, await copyReference(el));
  };

  if (reviewer && touch) {
    toggle = document.createElement("button");
    toggle.type = "button";
    toggle.textContent = "✎";
    toggle.setAttribute("aria-label", "Review mode");
    toggle.setAttribute("aria-pressed", "false");
    Object.assign(toggle.style, {
      position: "fixed",
      zIndex: "2147483646",
      left: "16px",
      bottom: "calc(16px + env(safe-area-inset-bottom))",
      width: "44px",
      height: "44px",
      borderRadius: "50%",
      border: "1.5px solid oklch(55% 0.16 155)",
      background: "oklch(99% 0.005 155)",
      color: "oklch(22% 0.03 155)",
      fontSize: "20px",
      boxShadow: "0 2px 8px rgba(0,0,0,0.28)",
    });
    toggle.addEventListener("click", () => {
      reviewMode = !reviewMode;
      toggle.setAttribute("aria-pressed", String(reviewMode));
      Object.assign(toggle.style, {
        background: reviewMode ? "oklch(55% 0.16 155)" : "oklch(99% 0.005 155)",
        color: reviewMode ? "oklch(99% 0.005 155)" : "oklch(22% 0.03 155)",
      });
      if (reviewMode) return showNotes();
      closeBox();
      hideNotes();
    });
    document.body.append(toggle);
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
  const refreshHighlight = () => {
    if (markers.length) showNotes();
    if (!activeEl || copiedTimer) return;
    if (!activeEl.isConnected) return hideHighlight();
    renderHighlight(activeEl);
    if (box) positionBox();
  };
  window.addEventListener("scroll", refreshHighlight, {
    passive: true,
    capture: true,
  });
  window.addEventListener("resize", refreshHighlight);
  window.visualViewport?.addEventListener("resize", refreshHighlight);
  window.visualViewport?.addEventListener("scroll", refreshHighlight);

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
