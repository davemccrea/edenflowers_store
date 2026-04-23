// Lightweight carousel — drop-in replacement for embla-carousel@8.
// Replace this file with the real package if richer features are needed:
//   https://www.embla-carousel.com
//
// API surface used by EmblaCarousel hook:
//   EmblaCarousel(root, options?) → { scrollPrev, scrollNext, destroy }
//   options: { loop?, align? }

export default function EmblaCarousel(root, options = {}) {
  const { loop = false } = options;

  const container = root.firstElementChild;
  if (!container) return { scrollPrev() {}, scrollNext() {}, destroy() {} };

  const slides = Array.from(container.children);
  let index = 0;

  // ── styles ───────────────────────────────────────────────────────────────
  root.style.overflow = "hidden";
  Object.assign(container.style, {
    display: "flex",
    transition: "transform 0.35s ease",
    willChange: "transform",
    userSelect: "none",
    webkitUserSelect: "none",
  });

  // ── positioning ──────────────────────────────────────────────────────────
  function slideWidth() {
    return slides[0]?.getBoundingClientRect().width ?? 0;
  }

  function goTo(i) {
    if (!loop) {
      i = Math.max(0, Math.min(i, slides.length - 1));
    } else {
      i = ((i % slides.length) + slides.length) % slides.length;
    }
    index = i;
    container.style.transform = `translateX(-${index * slideWidth()}px)`;
  }

  // ── drag / swipe ─────────────────────────────────────────────────────────
  let pointerStartX = 0;
  let dragging = false;

  function onPointerDown(e) {
    pointerStartX = e.clientX ?? e.touches?.[0]?.clientX ?? 0;
    dragging = true;
  }

  function onPointerUp(e) {
    if (!dragging) return;
    dragging = false;
    const endX = e.clientX ?? e.changedTouches?.[0]?.clientX ?? pointerStartX;
    const delta = pointerStartX - endX;
    if (Math.abs(delta) > 40) {
      delta > 0 ? scrollNext() : scrollPrev();
    }
  }

  root.addEventListener("mousedown", onPointerDown);
  root.addEventListener("mouseup", onPointerUp);
  root.addEventListener("touchstart", onPointerDown, { passive: true });
  root.addEventListener("touchend", onPointerUp);
  root.addEventListener("dragstart", (e) => e.preventDefault());

  // ── public API ───────────────────────────────────────────────────────────
  function scrollPrev() { goTo(index - 1); }
  function scrollNext() { goTo(index + 1); }

  function destroy() {
    root.removeEventListener("mousedown", onPointerDown);
    root.removeEventListener("mouseup", onPointerUp);
    root.removeEventListener("touchstart", onPointerDown);
    root.removeEventListener("touchend", onPointerUp);
    container.style.transform = "";
    container.style.transition = "";
    root.style.overflow = "";
  }

  return { scrollPrev, scrollNext, destroy };
}
