import { elementReference, findHeexSource } from "./dev_element_reference.mjs";

// In dev, Option+Click copies page context and a source-mapped element reference.
if (document.querySelector("[data-phx-loc]")) {
  let activeEl = null;
  let lastTarget = null;
  let selectionPath = [];
  let copiedTimer = null;
  let overlay = null;
  let label = null;
  let hint = null;

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
    // Modal drawers sit in the browser's top layer, above every body z-index.
    // Keep the picker in the same layer as the element being inspected.
    const host = el.closest(":popover-open, dialog:modal") || document.body;
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

    const src = findHeexSource(el);
    const sourceLabel = src
      ? `${src.mappedElement !== el ? "~" : ""}${shortFile(src.file)}:${src.location.split(":").pop()}`
      : "no source";
    label.textContent = `${tagSummary(el)} · ${sourceLabel}`;
    hint.textContent = flashText || "⌥↑ parent · ⌥↓ child · ⌥click copy";
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
    if (copiedTimer) return;
    activeEl = null;
    if (overlay) overlay.style.display = "none";
    if (label) label.style.display = "none";
  };

  document.addEventListener(
    "mousemove",
    (event) => {
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
      if (copiedTimer) return;
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
  };
  window.addEventListener("scroll", refreshHighlight, {
    passive: true,
    capture: true,
  });
  window.addEventListener("resize", refreshHighlight);

  const stopAltPointer = (event) => {
    if (!event.altKey) return;
    event.preventDefault();
    event.stopPropagation();
  };

  document.addEventListener("mousedown", stopAltPointer, true);
  document.addEventListener("pointerdown", stopAltPointer, true);

  document.addEventListener(
    "click",
    async (event) => {
      if (!event.altKey) return;
      const target = pickTarget(event.target);
      const el =
        target === lastTarget && activeEl?.isConnected ? activeEl : target;

      event.preventDefault();
      event.stopPropagation();

      let message;
      try {
        await navigator.clipboard.writeText(elementReference(el, document));
        message = "✓ Copied";
      } catch (error) {
        console.error("Could not copy element reference", error);
        message = "Could not copy — check clipboard permissions";
      }

      clearTimeout(copiedTimer);
      renderHighlight(el, message);
      copiedTimer = setTimeout(() => {
        copiedTimer = null;
        hideHighlight();
      }, 900);
    },
    true,
  );
}
