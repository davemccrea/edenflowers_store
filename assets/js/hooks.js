// @ts-check

import EmblaCarousel from "../vendor/embla-carousel.esm";

export const Hooks = {};

/**
 * Carousel for the Featured Blooms section.
 *
 * Markup contract (set in HomeLive):
 *   <div class="embla">
 *     <div class="embla__viewport" phx-hook="FeaturedCarousel" id="...">
 *       <ul class="embla__container">
 *         <li class="embla__slide">...</li>
 *       </ul>
 *     </div>
 *     <button class="embla__prev">…</button>
 *     <button class="embla__next">…</button>
 *     <div class="embla__dots"></div>
 *   </div>
 */
Hooks.FeaturedCarousel = {
  mounted() {
    // Buttons live in the section heading (sibling of .embla), so we scope
    // the lookup to the enclosing <section> rather than .embla itself.
    const scope = this.el.closest("section") || document;
    this.prevBtn = scope.querySelector(".embla__prev");
    this.nextBtn = scope.querySelector(".embla__next");
    this.dotsNode = scope.querySelector(".embla__dots");
    this.dotNodes = [];

    // Reduced-motion users skip the per-frame focal-point work entirely.
    // The breakpoint above which the effect is disabled is handled in CSS.
    this.reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    // slidesToScroll: 1 on mobile, 'auto' on >=md so an arrow click jumps a
    // full page of cards on desktop.
    this.embla = EmblaCarousel(this.el, {
      align: "center",
      containScroll: "trimSnaps",
      slidesToScroll: 1,
      breakpoints: {
        "(min-width: 768px)": { slidesToScroll: "auto" },
      },
    });

    this.boundOnSelect = this.onSelect.bind(this);
    this.boundOnReInit = this.onReInit.bind(this);
    this.boundOnTween = this.onTween.bind(this);

    if (this.prevBtn) {
      this.prevBtn.addEventListener("click", () => this.embla.scrollPrev());
    }
    if (this.nextBtn) {
      this.nextBtn.addEventListener("click", () => this.embla.scrollNext());
    }

    this.buildDots();
    this.setTweenFactor();
    this.embla.on("select", this.boundOnSelect);
    this.embla.on("reInit", this.boundOnReInit);
    this.embla.on("scroll", this.boundOnTween);
    this.embla.on("slideFocus", this.boundOnTween);
    this.onSelect();
    this.onTween();
  },

  updated() {
    if (this.embla) this.embla.reInit();
  },

  destroyed() {
    if (this.embla) this.embla.destroy();
  },

  /**
   * Compute the focal-point falloff multiplier. Scaling by snapList length
   * keeps the effect feeling consistent whether there are 3 or 30 snaps —
   * matches Embla's predefined Tween Scale / Tween Opacity examples.
   */
  setTweenFactor() {
    const TWEEN_FACTOR_BASE = 0.6;
    this.tweenFactor = TWEEN_FACTOR_BASE * this.embla.scrollSnapList().length;
  },

  /**
   * Per-frame focal-point effect: write each slide's distance-from-center
   * (clamped 0..1) to a CSS custom property so CSS can scale/fade neighbours.
   * Iterates by snap index and resolves slides via slideRegistry — correct
   * under slidesToScroll:'auto' grouping at md+. CSS gates which breakpoint
   * the effect actually applies at.
   */
  onTween(eventName) {
    if (this.reducedMotion) return;
    const engine = this.embla.internalEngine();
    const scrollProgress = this.embla.scrollProgress();
    const slidesInView = this.embla.slidesInView();
    const slideNodes = this.embla.slideNodes();
    const isScrollEvent = eventName === "scroll";

    this.embla.scrollSnapList().forEach((scrollSnap, snapIndex) => {
      const diffToTarget = scrollSnap - scrollProgress;

      engine.slideRegistry[snapIndex].forEach((slideIndex) => {
        // Per-frame: skip off-screen slides. On reInit / slideFocus / mount
        // we update everyone so freshly-revealed slides paint correctly.
        if (isScrollEvent && !slidesInView.includes(slideIndex)) return;
        const progress = Math.min(Math.abs(diffToTarget * this.tweenFactor), 1);
        slideNodes[slideIndex].style.setProperty(
          "--embla-progress",
          progress.toFixed(3),
        );
      });
    });
  },

  buildDots() {
    if (!this.dotsNode) return;
    // Localized template comes from a data attr on the viewport. Falls back
    // to English if missing so the carousel still works.
    // Sentinel "__N__" is replaced client-side. Using %{n} would trigger
    // Gettext binding-validation warnings server-side at every render.
    const tpl = this.el.dataset.dotLabelTemplate || "Go to slide __N__";
    const snapList = this.embla.scrollSnapList();
    this.dotsNode.innerHTML = snapList
      .map(
        (_, i) =>
          `<button type="button" class="embla__dot" aria-label="${tpl.replace("__N__", i + 1)}" aria-current="false"></button>`,
      )
      .join("");
    this.dotNodes = Array.from(this.dotsNode.querySelectorAll(".embla__dot"));
    this.dotNodes.forEach((node, i) => {
      node.addEventListener("click", () => this.embla.scrollTo(i));
    });
  },

  onSelect() {
    const selected = this.embla.selectedScrollSnap();
    this.dotNodes.forEach((node, i) => {
      const isSelected = i === selected;
      node.classList.toggle("embla__dot--selected", isSelected);
      node.setAttribute("aria-current", isSelected ? "true" : "false");
    });
    const canScroll = this.embla.canScrollPrev() || this.embla.canScrollNext();
    this.el
      .closest("section")
      ?.classList.toggle("embla--no-scroll", !canScroll);
    if (this.prevBtn) this.prevBtn.disabled = !this.embla.canScrollPrev();
    if (this.nextBtn) this.nextBtn.disabled = !this.embla.canScrollNext();
  },

  onReInit() {
    this.buildDots();
    this.setTweenFactor();
    this.onSelect();
    this.onTween();
  },
};

Hooks.CharacterCount = {
  mounted() {
    const textarea = this.el.querySelector("textarea");
    const charCountDisplay = this.el.querySelector("#char-count");

    updateCharCount();

    textarea.addEventListener("input", updateCharCount);

    function updateCharCount() {
      charCountDisplay.textContent = textarea.value.length;
    }
  },
};

/**
 * Re-runs the `.quantity-pulse` CSS animation each time the element's
 * data-quantity changes. Used on cart line-item quantity counters so the
 * digit visibly pulses when +/- is clicked, even though the same DOM node
 * is reused across LiveView morphs.
 *
 * Markup contract:
 *   <span phx-hook="PulseOnChange" data-quantity={quantity}>{quantity}</span>
 *
 * The matching keyframes live in app.css (`.quantity-pulse` /
 * `@keyframes quantity-pulse`).
 */
Hooks.PulseOnChange = {
  mounted() {
    this.last = this.el.dataset.quantity;
  },

  updated() {
    const next = this.el.dataset.quantity;
    if (next === this.last) return;
    this.el.classList.remove("quantity-pulse");
    // Force reflow so the browser registers the class removal before we
    // re-add it; otherwise the animation won't restart on rapid clicks.
    void this.el.offsetWidth;
    this.el.classList.add("quantity-pulse");
    this.last = next;
  },
};

Hooks.FocusElement = {
  mounted() {
    // Focus on the first form element when the page loads (step 1)
    requestAnimationFrame(() => {
      const firstForm = this.el.querySelector('[id$="-form-1"]');
      if (firstForm) {
        const firstInput = firstForm.querySelector(
          'input:not([type="hidden"]), textarea, select, button[type="submit"]',
        );
        if (firstInput) {
          /** @type {HTMLElement} */ (firstInput).focus();
        }
      }
    });

    this.handleEvent("focus-element", ({ id }) => {
      // Use requestAnimationFrame to ensure DOM has updated
      requestAnimationFrame(() => {
        const element = document.getElementById(id);
        if (!element) return;

        // Scroll the section heading to the top of the viewport. The section's
        // scroll-margin-top accounts for the fixed page header so the heading
        // doesn't land underneath it.
        element.scrollIntoView({ block: "start", behavior: "smooth" });

        // preventScroll keeps keyboard focus working without overriding the
        // scroll position we just set above.
        const firstInput = element.querySelector(
          'input:not([type="hidden"]), textarea, select, button[type="submit"]',
        );
        if (firstInput) {
          /** @type {HTMLElement} */ (firstInput).focus({
            preventScroll: true,
          });
        }
      });
    });
  },
};

/**
 * Navigate the calendar with the keyboard without a round trip to the server for each key press.
 * If the user tries to navigate to a date outside the visible month then the keydown event is
 * forwarded to the server and the server re-renders the view.
 *
 * Wire protocol (server <-> hook):
 *   - data-view-date           : ISO date of the currently focused cell
 *   - data-focusable-dates     : JSON array of ISO dates focusable client-side (current month)
 *   - data-key-targets (cell)  : JSON map { "ArrowUp": "2026-05-05", ... } of the date each
 *                                key would navigate to from this cell
 */
const NAV_KEYS = [
  "ArrowUp",
  "ArrowDown",
  "ArrowLeft",
  "ArrowRight",
  "Home",
  "End",
  "PageUp",
  "PageDown",
];

Hooks.CalendarHook = {
  mounted() {
    // Validate required elements and attributes
    if (!this.validateRequirements()) return;

    // Set initial tab index
    this.setTabIndex(this.viewDate);

    this.calendarGrid.addEventListener("keydown", (event) => {
      // Bail on modifier-key combos so browser/SR shortcuts (Ctrl+Home,
      // Shift+Arrow, etc.) still reach the host.
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
        return;
      }
      if (!NAV_KEYS.includes(event.key)) return;
      // Only intercept when a day button is the actual focus target — keeps
      // arrow keys passing through to anything else nested in the grid.
      if (!event.target.closest(`[id^="${this.id}-day-"]`)) return;
      event.preventDefault();
      this.handleKeyDown(event.key);
    });
  },

  updated() {
    this.focusableDates = this.getFocusableDates() || [];
    this.viewDate = this.getViewDate();
    this.setTabIndex(this.viewDate);

    // If the server just moved the view date in response to a cross-month
    // keyboard nav, restore DOM focus to the newly-promoted cell. Doing this
    // here (instead of in a pushEventTo callback) avoids racing the morph:
    // updated() runs after the patch has landed, so the target cell exists.
    if (this.pendingKeyboardNav) {
      this.pendingKeyboardNav = false;
      this.clientFocus(this.viewDate);
    }
  },

  /**
   * Handles the keydown event for the calendar grid.
   * @example
   * handleKeyDown("ArrowUp");
   * @param {String} key - The key pressed by the user.
   * @returns {void}
   */
  handleKeyDown(key) {
    // If focusable dates are missing/empty, every nav would otherwise fall
    // through to serverFocus and spam the server on each keypress.
    if (!this.focusableDates.length) return;

    // A server roundtrip is already in flight (held-key repeat across a month
    // boundary). Drop the event rather than queueing — the user can resume
    // navigating once focus lands on the newly-promoted cell.
    if (this.pendingKeyboardNav) return;

    // Read targets from the currently-focused cell, not the root: each cell's
    // targets are relative to its own date (ArrowDown from May 1 -> May 8,
    // ArrowDown from May 8 -> May 15, etc).
    const viewDateEl = this.getElement(`calendar-day-${this.viewDate}`);
    if (!viewDateEl) return;

    const targets = this.parseKeyTargets(viewDateEl);
    if (!targets) return;

    const nextDate = targets[key];
    if (!nextDate) {
      this.error(
        `Key '${key}' missing from data-key-targets on view date element.`,
      );
      return;
    }

    // This part is important - check if the next date is focusable by the client.
    // If not focusable the keydown event is forwarded to and handled on the server.
    if (!this.isClientFocusable(nextDate)) {
      return this.serverFocus(key);
    }

    this.clientFocus(nextDate);
    this.setTabIndex(nextDate);
    this.viewDate = nextDate;
  },

  /**
   * Parses the data-key-targets JSON map from a cell element.
   * @param {Element} el
   * @returns {Object<string, string> | null}
   */
  parseKeyTargets(el) {
    const raw = el.getAttribute("data-key-targets");
    if (!raw) {
      this.error(
        "Attribute 'data-key-targets' is missing on view date element.",
      );
      return null;
    }

    try {
      return JSON.parse(raw);
    } catch (error) {
      this.error(`Failed to parse 'data-key-targets': ${error.message}`);
      return null;
    }
  },

  //
  // Focus Management
  //

  /**
   * Moves focus to the given date.
   * @example
   * clientFocus("2023-06-01");
   * @param {String} date - The date to move the focus to.
   * @returns {void}
   */
  clientFocus(date) {
    if (!date) {
      this.error("Cannot focus on null date.");
      return;
    }

    const dateEl = this.getElement(`calendar-day-${date}`);
    if (dateEl) {
      /** @type {HTMLElement} */ (dateEl).focus();
    }
  },

  /**
   * Used when the focus is to be moved to a date that is not focusable by the client.
   * The server will rerender into the new month; updated() then restores DOM
   * focus to the newly-promoted view date via the `pendingKeyboardNav` flag.
   * @example
   * serverFocus("ArrowUp");
   * @param {String} key - The key pressed by the user.
   * @returns {void}
   */
  serverFocus(key) {
    this.pendingKeyboardNav = true;
    this.pushEventTo(this.el, "keydown", { key, viewDate: this.viewDate });
  },

  /**
   * Set tabindex="-1" on the focused element and set tabindex="0" on the element that will become focused.
   * At any given time, only one gridcell within the calendar grid can be in the tab sequence.
   * @example
   * setTabIndex("2023-06-01");
   * @param {String | null} nextDate - The date receiving focus.
   * @returns {void}
   */
  setTabIndex(nextDate = null) {
    // Remove focus from view date
    const viewDateEl = this.getElement(`calendar-day-${this.viewDate}`);
    if (viewDateEl) {
      viewDateEl.setAttribute("tabindex", "-1");
    }

    // Set focus on next date
    if (nextDate) {
      const nextDateEl = this.getElement(`calendar-day-${nextDate}`);
      if (nextDateEl) {
        nextDateEl.setAttribute("tabindex", "0");
      }
    }
  },

  /**
   * Validates all requirements for the hook to work properly
   * @returns {Boolean} Whether all requirements are met
   */
  validateRequirements() {
    // Check for ID
    this.id = this.el.getAttribute("id");
    if (!this.id) {
      this.error("Element must have an 'id' attribute.");
      return false;
    }

    // Check for view date
    this.viewDate = this.getViewDate();
    if (!this.viewDate) {
      this.error(`Attribute 'data-view-date' is required.`);
      return false;
    }

    // Check for focusable dates
    this.focusableDates = this.getFocusableDates();
    if (this.focusableDates === null) {
      this.error("Attribute 'data-focusable-dates' is required.");
      return false;
    }
    if (!this.focusableDates.length) {
      this.error("Attribute 'data-focusable-dates' must not be empty.");
      return false;
    }

    // Check for calendar grid
    this.calendarGrid = this.el.querySelector(`#${this.id}-grid`);
    if (!this.calendarGrid) {
      this.error(`Calendar grid with id '${this.id}-grid' not found.`);
      return false;
    }

    return true;
  },

  //
  // Utility Methods
  //

  /**
   * Gets an element by ID and logs an error if not found
   * @param {String} id - The element ID
   * @returns {Element | null} - The found element or null
   */
  getElement(id) {
    const element = document.getElementById(id);
    if (!element) {
      this.error(`Element with id "${id}" not found.`);
    }
    return element;
  },

  /**
   * Checks if the given date is focusable by the client.
   * A focusable date is a date within the current month.
   * @example
   * isClientFocusable("2023-06-01");
   * @param {String | null} date - The date to check.
   * @returns {Boolean}
   */
  isClientFocusable(date) {
    if (!date) return false;
    return this.focusableDates.includes(date);
  },

  getFocusableDates() {
    const focusableDatesAttr = this.el.getAttribute("data-focusable-dates");
    // Distinguish "attribute missing" (null) from "parsed but empty" ([]) so
    // validateRequirements can emit a single error for the missing-attr case.
    if (!focusableDatesAttr) return null;

    try {
      return JSON.parse(focusableDatesAttr);
    } catch (error) {
      this.error(`Failed to parse 'data-focusable-dates': ${error.message}`);
      return [];
    }
  },

  /**
   * Gets the view date from the element's data attribute.
   * @returns {String | null}
   */
  getViewDate() {
    return this.el.getAttribute("data-view-date");
  },

  /**
   * Logs error message to the console and forwards error to the server.
   * @example
   * error("Attribute 'data-focusable-dates' is required.");
   * @param {String} message - The error message to send to the server.
   * @returns {void}
   */
  error(message) {
    console.error(`CalendarHook Error: ${message}`);
    this.pushEventTo(this.el, "client-error", { message: message });
  },
};

Hooks.Stripe = {
  mounted() {
    this.returnUrl = this.el.getAttribute("data-return-url");
    if (!this.returnUrl) {
      return this.logAndPushError("data-return-url attribute is missing.");
    }

    this.clientSecret = this.el.getAttribute("data-client-secret");
    if (!this.clientSecret) {
      return this.logAndPushError("data-client-secret attribute is missing.");
    }

    this.publishableKey = this.el.getAttribute("data-publishable-key");
    if (!this.publishableKey) {
      return this.logAndPushError("data-publishable-key attribute is missing.");
    }

    this.stripeReadyJS = this.el.getAttribute("data-stripe-ready");
    if (!this.stripeReadyJS) {
      return this.logAndPushError("data-stripe-ready attribute is missing.");
    }

    this.stripeLoadingJS = this.el.getAttribute("data-stripe-loading");
    if (!this.stripeLoadingJS) {
      return this.logAndPushError("data-stripe-loading attribute is missing.");
    }

    this.stripeErrorMessage = document.getElementById("stripe-error-message");
    if (!this.stripeErrorMessage) {
      return this.logAndPushError("#stripe-error-message element not found.");
    }

    this.button = document.getElementById("payment-button");
    if (!this.button) {
      return this.logAndPushError("#payment-button element not found.");
    }

    this.paymentElement = document.getElementById("payment-element");
    if (!this.paymentElement) {
      return this.logAndPushError("#payment-element element not found.");
    }

    try {
      // @ts-ignore
      const stripe = Stripe(this.publishableKey);
      const elements = stripe.elements({
        clientSecret: this.clientSecret,
        appearance: this.buildAppearance(),
        // Stripe runs in a cross-origin iframe and can't see the host's
        // @font-face rules, so Open Sans must be loaded inside the iframe.
        fonts: [
          {
            cssSrc:
              "https://fonts.googleapis.com/css2?family=Open+Sans:ital,wght@0,300..800;1,300..800&display=swap",
          },
        ],
      });

      const paymentElement = elements.create("payment", {});
      paymentElement.mount("#payment-element");
      paymentElement.on("ready", (event) => {
        this.stripeReady();
      });

      this.handleEvent("stripe:process_payment", async () => {
        this.stripeLoading();
        this.stripeErrorMessage.textContent = ""; // Clear previous errors

        const { error } = await stripe.confirmPayment({
          elements,
          confirmParams: {
            return_url: this.returnUrl,
          },
        });

        if (error) {
          // Stripe shows validation errors inline

          if (error.type !== "validation_error") {
            this.logAndPushError("error confirming payment", error);
          }

          this.stripeReady(); // Re-enable button after payment error
        }

        // No 'else' needed, success is handled by Stripe redirecting to return_url
      });
    } catch (error) {
      const message =
        "Failed to initialize payment form. Please try again later.";
      this.logAndPushError(message, error);
      this.stripeReady(); // Re-enable button if initialization fails
    }
  },

  /**
   * Logs an error message and pushes a 'stripe:error' event to the server.
   * @param {string} message - The error message.
   * @param {object | null} [errorObject=null] - The original error object, if available.
   */
  logAndPushError(message, errorObject = null) {
    const msg = `Stripe Hook Error: ${message}`;
    console.error(msg, errorObject || "");
    this.pushEvent("stripe:error", {
      message: msg,
      details: errorObject || "",
    });
  },

  stripeReady() {
    this.liveSocket.execJS(this.el, this.stripeReadyJS);
  },

  stripeLoading() {
    this.liveSocket.execJS(this.el, this.stripeLoadingJS);
  },

  /**
   * Build a Stripe Elements `appearance` config from the live daisyUI theme
   * tokens on `:root`, so the Payment Element matches our `<input class="input
   * input-lg">` styling. Stripe Elements run in an iframe and can't be styled
   * with CSS, so we resolve the values up-front and pass them in.
   *
   * daisyUI input model (mirrored here):
   *   - rest: border-color = color-mix(base-content 20%, transparent)
   *   - focus / focus-within: border-color flips to full base-content;
   *                           outline 2px solid base-content with 2px offset
   *   - invalid: border-color and focus outline flip to --color-error
   *   - input-lg: 48px tall, 18px font, 12px horizontal padding
   */
  buildAppearance() {
    const css = getComputedStyle(document.documentElement);
    const v = (name, fallback = "") =>
      css.getPropertyValue(name).trim() || fallback;

    const baseContent = v("--color-base-content", "#1f2937");
    const base100 = v("--color-base-100", "#ffffff");
    const primary = v("--color-primary", "#0570de");
    const error = v("--color-error", "#dc2626");

    const subtleBorder = `color-mix(in oklab, ${baseContent} 20%, transparent)`;

    return {
      theme: "flat",
      variables: {
        colorPrimary: primary,
        colorBackground: base100,
        colorText: baseContent,
        colorDanger: error,
        fontFamily: v("--font-sans", "system-ui, sans-serif"),
        // 16px is the host body baseline; per-element sizes are set in `rules`.
        fontSizeBase: "16px",
        borderRadius: v("--radius-field", "0.25rem"),
        spacingUnit: "4px",
      },
      rules: {
        ".Input": {
          backgroundColor: base100,
          border: `1px solid ${subtleBorder}`,
          boxShadow: "none",
          fontSize: "18px",
          fontWeight: "400",
          lineHeight: "27px",
          // 10.5px vertical + 18px font + 27px line-height ≈ 48px (input-lg).
          padding: "10.5px 12px",
        },
        ".Input:focus": {
          backgroundColor: base100,
          border: `1px solid ${baseContent}`,
          outline: `2px solid ${baseContent}`,
          outlineOffset: "2px",
          boxShadow: "none",
        },
        ".Input--invalid": {
          backgroundColor: base100,
          border: `1px solid ${error}`,
          boxShadow: "none",
        },
        ".Input--invalid:focus": {
          backgroundColor: base100,
          border: `1px solid ${error}`,
          outline: `2px solid ${error}`,
          outlineOffset: "2px",
          boxShadow: "none",
        },
        ".Label": {
          color: baseContent,
          fontFamily: v("--font-sans", "system-ui, sans-serif"),
          fontSize: "16px",
          fontWeight: "400",
          lineHeight: "24px",
        },
        ".Error": {
          color: error,
          fontFamily: v("--font-sans", "system-ui, sans-serif"),
          fontSize: "14px",
          fontWeight: "400",
          lineHeight: "20px",
          marginTop: "6px",
        },
      },
    };
  },
};

Hooks.FlashHandler = {
  mounted() {
    this.initAlerts();
  },
  updated() {
    this.initAlerts();
  },

  initAlerts() {
    for (const el of Array.from(this.el.children)) {
      if (el.dataset.initialized) continue;
      el.dataset.initialized = "true";
      const key = el.dataset.key;
      const duration = parseInt(el.dataset.duration || "5000", 10);
      el.querySelector("[data-dismiss]")?.addEventListener("click", () =>
        this.dismiss(el, key),
      );
      if (duration > 0) setTimeout(() => this.dismiss(el, key), duration);
    }
  },

  dismiss(el, key) {
    if (el.dataset.dismissing) return;
    el.dataset.dismissing = "true";
    setTimeout(() => {
      if (key) this.pushEvent("lv:clear-flash", { key });
      else el.remove();
    }, 240);
  },

  disconnected() {
    if (document.getElementById("flash-disconnected")) return;
    const msg = this.el.getAttribute("data-disconnected-message");
    const div = document.createElement("div");
    div.id = "flash-disconnected";
    div.className = "toast-item";
    div.dataset.key = "warning";
    // role="alert" implies aria-live="assertive" but some AT/browser combos
    // miss it on dynamically-added nodes — set both explicitly.
    div.setAttribute("role", "alert");
    div.setAttribute("aria-live", "assertive");
    div.setAttribute("aria-atomic", "true");
    div.innerHTML = `
      <div class="toast-item__head">
        <p class="toast-item__eyebrow">Notice</p>
      </div>
      <p class="toast-item__body"></p>`;
    // Note: the disconnected banner has no dismiss button — it's auto-removed
    // when the socket reconnects (see reconnected() below).
    div.querySelector(".toast-item__body").textContent = msg;
    this.el.appendChild(div);
  },

  reconnected() {
    const banner = document.getElementById("flash-disconnected");
    if (!banner) return;
    this.dismiss(banner, null);

    // Announce the resolution politely so SR users hear that connection is back.
    const reconnectedMsg = this.el.getAttribute("data-reconnected-message");
    if (!reconnectedMsg) return;
    const note = document.createElement("div");
    note.className = "sr-only";
    note.setAttribute("role", "status");
    note.setAttribute("aria-live", "polite");
    note.textContent = reconnectedMsg;
    this.el.appendChild(note);
    setTimeout(() => note.remove(), 3000);
  },
};

Hooks.HotFxShyHeader = {
  mounted() {
    this.hideJS = this.el.getAttribute("data-hide");
    this.showJS = this.el.getAttribute("data-show");

    this.lastScroll = 0;
    this.lastMaxScroll = 0;

    this.boundHandleScroll = this.handleScroll.bind(this);

    document.addEventListener("scroll", this.boundHandleScroll);
  },

  destroyed() {
    document.removeEventListener("scroll", this.boundHandleScroll);
  },

  handleScroll() {
    if (window.scrollY > Math.max(150, this.lastScroll)) {
      this.liveSocket.execJS(this.el, this.hideJS);
    } else if (window.scrollY < this.lastMaxScroll - 150) {
      this.liveSocket.execJS(this.el, this.showJS);
      this.lastMaxScroll = window.scrollY;
    }
    this.lastScroll = window.scrollY;
    if (window.scrollY > this.lastMaxScroll) {
      this.lastMaxScroll = window.scrollY;
    }
  },
};

export default Hooks;
