// In dev (where Phoenix renders data-phx-loc and debug_heex_annotations),
// hold Option (Alt) to preview elements and Option+Click to copy a single-line
// inline reference you can paste straight into a sentence for an LLM.
if (document.querySelector("[data-phx-loc]")) {
  let activeEl = null;
  let lastTarget = null;
  let copiedTimer = null;
  let overlay = null;
  let label = null;

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
      display: "none",
    });

    document.body.append(overlay, label);
  };

  const prevCommentCaller = (commentNode) => {
    let prev = commentNode.previousSibling;
    while (prev?.nodeType === Node.TEXT_NODE && !prev.nodeValue.trim()) {
      prev = prev.previousSibling;
    }
    return prev?.nodeType === Node.COMMENT_NODE
      ? prev.nodeValue.trim().match(/^@caller\s+(\S+:\d+)/)?.[1]
      : null;
  };

  const findHeexSource = (startNode) => {
    let depth = 0;
    let slot = null;
    let node = startNode;

    while (node) {
      if (node.nodeType === Node.COMMENT_NODE) {
        const text = node.nodeValue.trim();
        const close = text.match(/^<\/([^>]+)>$/);
        const open = text.match(/^<([^>]+)>\s+(\S+):(\d+)/);

        if (close) {
          depth++;
        } else if (open) {
          if (depth > 0) {
            depth--;
          } else if (open[1].startsWith(":") && !slot) {
            slot = { name: open[1], file: open[2], line: open[3] };
          } else {
            return {
              component: open[1],
              file: slot ? slot.file : open[2],
              componentFile: slot ? `${open[2]}:${open[3]}` : null,
              slot: slot?.name,
              caller: prevCommentCaller(node),
            };
          }
        }
      }
      node = node.previousSibling || node.parentNode;
    }
    return null;
  };

  const tagSummary = (el) => {
    const tag = el.tagName.toLowerCase();
    const id = el.id ? `#${el.id}` : "";
    const cls = [...el.classList]
      .slice(0, 2)
      .map((c) => `.${c}`)
      .join("");
    return `${tag}${id}${cls}`;
  };

  const elementSnippet = (el) => {
    const raw =
      el.innerText?.trim() ||
      el.getAttribute("aria-label") ||
      el.getAttribute("placeholder") ||
      el.getAttribute("alt") ||
      el.getAttribute("name") ||
      "";
    const clean = raw.replace(/\s+/g, " ").slice(0, 50);
    return clean ? `"${clean}${raw.length > 50 ? "…" : ""}"` : null;
  };

  const shortFile = (path) => path?.split("/").slice(-2).join("/") ?? "";

  const renderHighlight = (el, flashText = null) => {
    ensureOverlay();
    // Modal drawers sit in the browser's top layer, above every body z-index.
    // Keep the picker in the same layer as the element being inspected.
    const host = el.closest("dialog:modal") || document.body;
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

    const loc = el.getAttribute("data-phx-loc");
    const src = findHeexSource(el);
    const fnName = src?.component?.split(".").pop();
    label.textContent =
      flashText ||
      [
        tagSummary(el),
        fnName && `<.${fnName}>`,
        src ? `${shortFile(src.file)}:${loc}` : `line ${loc}`,
      ]
        .filter(Boolean)
        .join(" · ");

    const top =
      rect.top > 28
        ? rect.top - 24
        : Math.min(rect.bottom + 4, innerHeight - 24);
    const left = Math.max(4, Math.min(rect.left, innerWidth - 260));
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
      lastTarget = event.target;
      if (!event.altKey) return hideHighlight();
      if (copiedTimer) return;
      const el = event.target.closest?.("[data-phx-loc]");
      if (!el || el === activeEl) return;
      activeEl = el;
      renderHighlight(activeEl);
    },
    { passive: true },
  );

  document.addEventListener("keydown", (event) => {
    if (event.key === "Alt" && !activeEl && !copiedTimer) {
      const el = lastTarget?.closest?.("[data-phx-loc]");
      if (el) {
        activeEl = el;
        renderHighlight(activeEl);
      }
    }
  });

  document.addEventListener("keyup", (event) => {
    if (event.key === "Alt") hideHighlight();
  });

  window.addEventListener("blur", hideHighlight);
  window.addEventListener(
    "scroll",
    () => activeEl && !copiedTimer && renderHighlight(activeEl),
    { passive: true },
  );

  const stopAltPointer = (event) => {
    if (!event.altKey) return;
    if (!event.target.closest?.("[data-phx-loc]")) return;
    event.preventDefault();
    event.stopPropagation();
  };

  document.addEventListener("mousedown", stopAltPointer, true);
  document.addEventListener("pointerdown", stopAltPointer, true);

  document.addEventListener(
    "click",
    (event) => {
      if (!event.altKey) return;
      const el = activeEl || event.target.closest?.("[data-phx-loc]");
      if (!el) return;

      event.preventDefault();
      event.stopPropagation();

      const loc = el.getAttribute("data-phx-loc");
      const src = findHeexSource(el);
      const snippet = elementSnippet(el);
      const sameLoc = [...document.querySelectorAll(`[data-phx-loc="${loc}"]`)];
      const idx =
        sameLoc.length > 1
          ? `#${sameLoc.indexOf(el) + 1}/${sameLoc.length}`
          : null;

      const where = [
        src ? `${src.file}:${loc}` : `line ${loc}`,
        src?.caller && `called from ${src.caller}`,
      ]
        .filter(Boolean)
        .join(", ");

      const what = [`<${tagSummary(el)}>`, idx, snippet]
        .filter(Boolean)
        .join(" ");

      navigator.clipboard.writeText(`[${what} at ${where}]`);

      clearTimeout(copiedTimer);
      renderHighlight(
        el,
        `✓ Copied ${src ? `${shortFile(src.file)}:${loc}` : `line ${loc}`}`,
      );
      copiedTimer = setTimeout(() => {
        copiedTimer = null;
        hideHighlight();
      }, 900);
    },
    true,
  );
}
