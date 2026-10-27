import {
  elementReference,
  findHeexSource,
  selectorFor,
} from "./dev_element_reference.mjs";

// Option+Click on an element. In dev it copies page context and a
// source-mapped element reference. For reviewers (in dev or production) it
// also opens a box to leave a review note on the element.
const dev = !!document.querySelector("[data-phx-loc]");
const reviewer = document.body.hasAttribute("data-reviewer");

if (dev || reviewer) {
  let activeEl = null;
  let lastTarget = null;
  let selectionPath = [];
  let copiedTimer = null;
  let overlay = null;
  let label = null;
  let hint = null;
  let box = null;

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
  };

  const noteFor = (el, body) => ({
    body,
    path: location.pathname + location.search,
    locale: document.documentElement.lang,
    viewport: `${innerWidth}x${innerHeight}`,
    selector: selectorFor(el).slice(0, 2000),
    element_text: el.innerText?.trim().replace(/\s+/g, " ").slice(0, 500),
    element_html: el.outerHTML.slice(0, 2000),
    source: findHeexSource(el)?.location,
  });

  const openBox = (el, heading) => {
    box?.remove();
    activeEl = el;
    box = document.createElement("form");
    renderHighlight(el);

    Object.assign(box.style, {
      position: "fixed",
      zIndex: "2147483647",
      width: "320px",
      padding: "10px",
      display: "grid",
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
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      fontSize: "11px",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap",
    });

    const textarea = document.createElement("textarea");
    textarea.rows = 4;
    textarea.placeholder = "What should change here?";
    textarea.setAttribute("aria-label", "Review note");
    Object.assign(textarea.style, {
      width: "100%",
      padding: "6px",
      border: "1px solid oklch(80% 0.02 155)",
      borderRadius: "4px",
      font: "inherit",
      resize: "vertical",
    });

    const status = document.createElement("span");
    status.textContent = "⌘↵ to save, Esc to cancel";
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
    actions.append(status, cancel, save);
    box.append(title, textarea, actions);

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
      const response = await fetch("/review-notes", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": document.querySelector("meta[name='csrf-token']")
            .content,
        },
        body: JSON.stringify(noteFor(el, body)),
      }).catch(() => null);

      if (response?.ok) {
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
    if (event.key === "Alt") hideHighlight();
  });

  window.addEventListener("blur", hideHighlight);
  const refreshHighlight = () => {
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

  const stopAltPointer = (event) => {
    if (!event.altKey || box?.contains(event.target)) return;
    event.preventDefault();
    event.stopPropagation();
  };

  document.addEventListener("mousedown", stopAltPointer, true);
  document.addEventListener("pointerdown", stopAltPointer, true);

  document.addEventListener(
    "click",
    async (event) => {
      if (!event.altKey || box?.contains(event.target)) return;
      const target = pickTarget(event.target);
      const el =
        target === lastTarget && activeEl?.isConnected ? activeEl : target;

      event.preventDefault();
      event.stopPropagation();

      if (!dev) return openBox(el, tagSummary(el));

      let message;
      try {
        await navigator.clipboard.writeText(elementReference(el, document));
        message = "✓ Copied";
      } catch (error) {
        console.error("Could not copy element reference", error);
        message = "Could not copy — check clipboard permissions";
      }

      if (reviewer) openBox(el, `${message} · ${tagSummary(el)}`);
      else flash(el, message);
    },
    true,
  );
}
