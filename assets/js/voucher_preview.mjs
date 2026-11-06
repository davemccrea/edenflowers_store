const TYPING = "textarea, input[type=text], input[type=email]";
const CONTROLS = "input, textarea, select, button, a, [role=button]";

export const VoucherPreview = {
  mounted() {
    this.form = this.el.closest("form");
    this.viewport = window.visualViewport;
    this.closedHeight = this.viewport?.height ?? window.innerHeight;
    this.closedWidth = window.innerWidth;
    this.keyboardOpen = false;
    this.fieldTooTall = false;
    this.header = document.getElementById("hotfx-shy-header");
    this.hasScrollEnd = "onscrollend" in document;

    this.renderPreview = () => {
      if (this.frame) return;
      this.frame = requestAnimationFrame(() => {
        this.frame = null;
        if (!this.keyboardOpen) {
          if (this.el.hasAttribute("data-keyboard-open")) {
            this.el.setAttribute("data-preview-returning", "");
            this.el.removeAttribute("data-keyboard-open");
          }
          if (this.restoreField?.isConnected && !this.scrolling)
            this.keepVisible(this.restoreField, { animate: true });
        }
        const bounds = this.el.getBoundingClientRect();
        const viewportTop = this.viewport?.offsetTop ?? 0;
        this.el.toggleAttribute(
          "data-preview-owns-top",
          Boolean(
            window.matchMedia("(width < 64rem)").matches &&
              getComputedStyle(this.el).position === "sticky" &&
              bounds.top < viewportTop + (this.header?.offsetHeight ?? 0) &&
              bounds.bottom > viewportTop,
          ),
        );
      });
    };
    this.onScrollEnd = () => {
      if (!this.scrolling) return;
      this.scrolling = false;
      clearTimeout(this.scrollTimer);
      this.renderPreview();
    };
    this.onDocumentScroll = () => {
      this.renderPreview();
      // Older Safari has no scrollend. This timer releases the scroll guard;
      // it never postpones the start of a correction.
      if (this.scrolling && !this.hasScrollEnd) {
        clearTimeout(this.scrollTimer);
        this.scrollTimer = setTimeout(this.onScrollEnd, 100);
      }
    };
    this.stopScroll = () => {
      if (!this.scrolling) return;
      this.scrolling = false;
      clearTimeout(this.scrollTimer);
      window.scrollTo({
        top: window.scrollY,
        left: window.scrollX,
        behavior: "instant",
      });
    };

    this.updateViewport = () => {
      const height = this.viewport?.height ?? window.innerHeight;
      const mobile = window.matchMedia("(width < 64rem)").matches;
      const unzoomed =
        !this.viewport || Math.abs(this.viewport.scale - 1) < 0.05;
      if (window.innerWidth !== this.closedWidth) {
        this.closedWidth = window.innerWidth;
        this.closedHeight = height;
        this.keyboardOpen = false;
        this.fieldTooTall = false;
        this.el.removeAttribute("data-field-too-tall");
        this.restoreField = null;
      }

      const wasOpen = this.keyboardOpen;
      // Remember the unobscured height: Safari can change innerHeight along
      // with the visual viewport, and Done may leave the field focused or blur it.
      this.keyboardOpen = Boolean(
        mobile &&
          unzoomed &&
          this.editedField &&
          (this.viewport
            ? this.closedHeight - height > 120
            : document.activeElement === this.editedField),
      );
      if (!mobile || !unzoomed) this.restoreField = null;
      if (unzoomed && !this.keyboardOpen) {
        this.closedHeight = Math.max(this.closedHeight, height);
      }
      if (wasOpen && !this.keyboardOpen && mobile && unzoomed) {
        this.restoreField = this.editedField;
      }

      if (this.keyboardOpen) {
        this.el.setAttribute("data-keyboard-open", "");
        this.el.removeAttribute("data-preview-returning");
      }
      this.renderPreview();
    };

    this.onFocusIn = ({ target }) => {
      if (!target.matches(CONTROLS)) return;
      this.restoreField = null;
      this.stopScroll();
      this.editedField =
        this.form.contains(target) && target.matches(TYPING) ? target : null;
      this.fieldTooTall = false;
      this.el.removeAttribute("data-field-too-tall");
      this.updateViewport();
    };
    this.onPointerDown = ({ target }) => {
      this.restoreField = null;
      this.stopScroll();
      const control = target.closest(CONTROLS);
      if (control && control !== this.editedField) {
        this.editedField =
          this.form.contains(control) && control.matches(TYPING)
            ? control
            : null;
      }
    };
    this.onScrollIntent = () => {
      this.restoreField = null;
      this.stopScroll();
    };
    this.onFocusOut = () => {
      clearTimeout(this.focusTimer);
      this.focusTimer = setTimeout(() => {
        const active = document.activeElement;
        if (
          this.keyboardOpen &&
          this.editedField &&
          !active?.matches(CONTROLS)
        ) {
          // Safari blurs Done before updating the visual viewport. Position the
          // field during dismissal, leaving the preview in normal flow until
          // the keyboard is actually gone.
          this.restoreField = this.editedField;
          this.keepVisible(this.editedField, {
            animate: true,
            anticipateClose: true,
          });
        }
        this.updateViewport();
      });
    };
    document.addEventListener("focusin", this.onFocusIn);
    document.addEventListener("pointerdown", this.onPointerDown, true);
    document.addEventListener("keydown", this.onScrollIntent);
    document.addEventListener("wheel", this.onScrollIntent, { passive: true });
    document.addEventListener("scroll", this.onDocumentScroll, {
      passive: true,
    });
    document.addEventListener("scrollend", this.onScrollEnd);
    this.form.addEventListener("focusout", this.onFocusOut);
    this.viewport?.addEventListener("resize", this.updateViewport);
    this.viewport?.addEventListener("scroll", this.updateViewport);
    window.addEventListener("resize", this.updateViewport);

    this.handleEvent("focus-first-error", () => {
      requestAnimationFrame(() => {
        const invalid = this.form.querySelector('[aria-invalid="true"]');
        if (!invalid) return;
        this.restoreField = null;
        invalid.focus({ preventScroll: true });
        this.keepVisible(invalid);
      });
    });
    this.updateViewport();
  },

  keepVisible(field, { animate = false, anticipateClose = false } = {}) {
    const mobile = window.matchMedia("(width < 64rem)").matches;
    const target = field.closest("fieldset") ?? field;
    const bounds = target.getBoundingClientRect();
    const viewportTop = anticipateClose ? 0 : (this.viewport?.offsetTop ?? 0);
    const height = anticipateClose
      ? this.closedHeight
      : (this.viewport?.height ?? window.innerHeight);
    const gap = 16;
    const headerHeight =
      document.getElementById("hotfx-shy-header")?.offsetHeight ?? 0;
    const bottom =
      viewportTop +
      height -
      Math.max(
        gap,
        parseFloat(getComputedStyle(document.body).paddingBottom) || 0,
      );

    this.el.removeAttribute("data-field-too-tall");
    const previewHeight = this.el.getBoundingClientRect().height;
    const fadeHeight =
      parseFloat(getComputedStyle(this.el, "::after").height) || 0;
    const sticky =
      mobile &&
      (anticipateClose
        ? window.matchMedia("(height >= 40rem)").matches
        : getComputedStyle(this.el).position === "sticky");
    const previewTop = viewportTop + previewHeight + fadeHeight + gap;
    const crowded = sticky && bounds.height > bottom - previewTop;
    this.fieldTooTall = crowded;
    this.el.toggleAttribute("data-field-too-tall", crowded);

    // Reserve the full header height when the preview scrolls away: scrolling
    // upwards can bring the shy header back before its offset is published.
    const top =
      viewportTop +
      (sticky && !crowded ? previewHeight + fadeHeight : headerHeight) +
      gap;
    const overlap =
      bounds.top < top || bounds.height > bottom - top
        ? bounds.top - top
        : bounds.bottom > bottom
          ? bounds.bottom - bottom
          : 0;
    const maxScroll = Math.max(
      0,
      document.documentElement.scrollHeight -
        document.documentElement.clientHeight,
    );
    const delta =
      Math.max(0, Math.min(maxScroll, window.scrollY + overlap)) -
      window.scrollY;
    // Native smooth scrolling rounds positions; don't start another animation
    // for a pixel or two inside the field's existing clearance.
    if (Math.abs(delta) > 2) {
      this.scrolling =
        animate &&
        !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      window.scrollBy({
        top: delta,
        behavior: this.scrolling ? "smooth" : "instant",
      });
      if (this.scrolling) this.scrollTimer = setTimeout(this.onScrollEnd, 500);
    }
  },

  updated() {
    this.el.toggleAttribute("data-field-too-tall", this.fieldTooTall);
    this.updateViewport();
  },

  destroyed() {
    clearTimeout(this.focusTimer);
    clearTimeout(this.scrollTimer);
    cancelAnimationFrame(this.frame);
    document.removeEventListener("focusin", this.onFocusIn);
    document.removeEventListener("pointerdown", this.onPointerDown, true);
    document.removeEventListener("keydown", this.onScrollIntent);
    document.removeEventListener("wheel", this.onScrollIntent);
    document.removeEventListener("scroll", this.onDocumentScroll);
    document.removeEventListener("scrollend", this.onScrollEnd);
    this.form.removeEventListener("focusout", this.onFocusOut);
    this.viewport?.removeEventListener("resize", this.updateViewport);
    this.viewport?.removeEventListener("scroll", this.updateViewport);
    window.removeEventListener("resize", this.updateViewport);
  },
};
