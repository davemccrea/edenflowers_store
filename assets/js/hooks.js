// @ts-check

import EmblaCarousel from "../vendor/embla-carousel.esm";
import PhotoSwipeLightbox from "../vendor/photoswipe-lightbox.esm";
import PhotoSwipe from "../vendor/photoswipe.esm";
import {
  clearOrderAlerts,
  currentSubscription,
  pushSupported,
  resyncSubscription,
  subscribeDevice,
  unsubscribeDevice,
} from "./push";

export const Hooks = {};

/**
 * Carousel for the Featured Blooms section.
 *
 * Markup contract (set in HomeLive):
 *   <div class="embla">
 *     <div class="embla__viewport" phx-hook="FeaturedCarousel" id="...">
 *       <div class="embla__container">
 *         <div class="embla__slide" role="group">...</div>
 *       </div>
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

Hooks.FocusElement = {
  // No autofocus on page load: on a phone it opens the keyboard over the page
  // before the customer has seen it.
  mounted() {
    this.handleEvent("focus-element", ({ id, focus = true }) => {
      requestAnimationFrame(() => {
        const element = document.getElementById(id);
        if (!element) return;

        // Scroll the section heading to the top of the viewport. The section's
        // scroll-margin-top accounts for the fixed page header so the heading
        // doesn't land underneath it.
        const reducedMotion = window.matchMedia(
          "(prefers-reduced-motion: reduce)",
        ).matches;
        element.scrollIntoView({
          block: "start",
          behavior: reducedMotion ? "auto" : "smooth",
        });

        if (!focus) return;

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

    this.handleEvent("focus-first-error", () => {
      requestAnimationFrame(() => {
        const invalid = this.el.querySelector('[aria-invalid="true"]');
        if (!invalid) return;

        // The delivery date's invalid input is hidden behind the calendar, so
        // scroll to the nearest visible ancestor (its fieldset) instead and
        // focus the calendar's roving tabindex day.
        let target = invalid;
        while (target && !target.checkVisibility())
          target = target.parentElement;
        const focusTarget = target?.querySelector('[tabindex="0"]') ?? invalid;

        const reducedMotion = window.matchMedia(
          "(prefers-reduced-motion: reduce)",
        ).matches;
        target?.scrollIntoView({
          block: "center",
          behavior: reducedMotion ? "auto" : "smooth",
        });
        /** @type {HTMLElement} */ (focusTarget).focus({ preventScroll: true });
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
    if (!this.validateRequirements()) return;

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

    // Arrow keys within the month move focus without telling the server, so
    // a re-render for anything else still carries the old view date. Only a
    // view date the server changed replaces the client's.
    const serverViewDate = this.getViewDate();
    if (serverViewDate !== this.serverViewDate) {
      this.serverViewDate = serverViewDate;
      this.viewDate = serverViewDate;
    }
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

  /** @param {string} key */
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
    const viewDateEl = this.getElement(`${this.id}-day-${this.viewDate}`);
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

    // A date not in data-focusable-dates is the server's to move to.
    if (!this.isClientFocusable(nextDate)) {
      return this.serverFocus(key);
    }

    this.clientFocus(nextDate);
    this.setTabIndex(nextDate);
    this.viewDate = nextDate;
  },

  /**
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

  /** @param {string} date */
  clientFocus(date) {
    if (!date) {
      this.error("Cannot focus on null date.");
      return;
    }

    const dateEl = this.getElement(`${this.id}-day-${date}`);
    if (dateEl) {
      /** @type {HTMLElement} */ (dateEl).focus();
    }
  },

  /**
   * Used when the focus is to be moved to a date that is not focusable by the client.
   * The server will rerender into the new month; updated() then restores DOM
   * focus to the newly-promoted view date via the `pendingKeyboardNav` flag.
   * @param {string} key
   */
  serverFocus(key) {
    this.pendingKeyboardNav = true;
    this.pushEventTo(this.el, "keydown", { key, viewDate: this.viewDate });
  },

  /**
   * Only one gridcell within the calendar grid is in the tab sequence at a time.
   * @param {string | null} nextDate
   */
  setTabIndex(nextDate = null) {
    const viewDateEl = this.getElement(`${this.id}-day-${this.viewDate}`);
    if (viewDateEl) {
      viewDateEl.setAttribute("tabindex", "-1");
    }

    if (nextDate) {
      const nextDateEl = this.getElement(`${this.id}-day-${nextDate}`);
      if (nextDateEl) {
        nextDateEl.setAttribute("tabindex", "0");
      }
    }
  },

  /** @returns {boolean} */
  validateRequirements() {
    this.id = this.el.getAttribute("id");
    if (!this.id) {
      this.error("Element must have an 'id' attribute.");
      return false;
    }

    this.viewDate = this.getViewDate();
    this.serverViewDate = this.viewDate;
    if (!this.viewDate) {
      this.error(`Attribute 'data-view-date' is required.`);
      return false;
    }

    this.focusableDates = this.getFocusableDates();
    if (this.focusableDates === null) {
      this.error("Attribute 'data-focusable-dates' is required.");
      return false;
    }
    if (!this.focusableDates.length) {
      this.error("Attribute 'data-focusable-dates' must not be empty.");
      return false;
    }

    this.calendarGrid = this.el.querySelector(`#${this.id}-grid`);
    if (!this.calendarGrid) {
      this.error(`Calendar grid with id '${this.id}-grid' not found.`);
      return false;
    }

    return true;
  },

  /**
   * @param {string} id
   * @returns {Element | null}
   */
  getElement(id) {
    const element = document.getElementById(id);
    if (!element) {
      this.error(`Element with id "${id}" not found.`);
    }
    return element;
  },

  /**
   * A focusable date is a date within the current month.
   * @param {string | null} date
   * @returns {boolean}
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

  /** @returns {string | null} */
  getViewDate() {
    return this.el.getAttribute("data-view-date");
  },

  /**
   * Logs to the console and forwards the error to the server.
   * @param {string} message
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

    // data-mode="setup" saves a card without charging it.
    this.mode = this.el.dataset.mode;
    this.amount = Number(this.el.dataset.amount);
    if (this.mode === "payment" && !this.amount) {
      return this.logAndPushError("data-amount attribute is missing.");
    }
    this.setupFutureUsage = this.el.dataset.setupFutureUsage;

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
      const elements = (this.elements = stripe.elements({
        ...this.intentOptions(),
        customerSessionClientSecret:
          this.el.dataset.customerSessionClientSecret || undefined,
        appearance: this.buildAppearance(),
        // Stripe has no "sv-FI", so pass the bare language ("en", "sv", "fi").
        locale: document.documentElement.lang.split(/[-_]/)[0],
        // Stripe runs in a cross-origin iframe and can't see the host's
        // @font-face rules, so Open Sans must be loaded inside the iframe.
        // Self-hosted rather than Google Fonts, which would send customers' IPs to Google.
        fonts: [
          {
            family: "Open Sans",
            src: `url(${new URL("/fonts/OpenSans-Variable.woff2", window.location.origin)}) format("woff2")`,
            weight: "300 800",
          },
        ],
      }));

      const paymentElement = elements.create("payment", {
        paymentMethodOrder: ["mobilepay", "card"],
        defaultValues: {
          billingDetails: {
            name: this.el.dataset.billingName,
            email: this.el.dataset.billingEmail,
            phone: this.el.dataset.billingPhone,
          },
        },
      });
      paymentElement.mount("#payment-element");
      paymentElement.on("ready", (event) => {
        this.stripeReady();
      });
      paymentElement.on("loaderror", (event) => {
        this.logAndPushError("payment element failed to load", event.error);
      });

      // The server couldn't create the PaymentIntent, so Stripe never started.
      this.handleEvent("stripe:ready", () => this.stripeReady());

      // Safari only opens the Apple Pay sheet inside the tap, so wallets are
      // collected here, before "pay" makes its round trip to the server.
      this.el.addEventListener("submit", () => {
        this.submitted = elements.submit();
      });

      this.handleEvent("stripe:process_payment", async ({ client_secret }) => {
        this.stripeLoading();
        this.stripeErrorMessage.textContent = ""; // Clear previous errors

        const { error: submitError } = await this.submitted;
        if (submitError) {
          return this.handleStripeError(
            submitError,
            "error collecting payment details",
          );
        }

        const confirm =
          this.mode === "setup" ? stripe.confirmSetup : stripe.confirmPayment;
        const { error } = await confirm.call(stripe, {
          elements,
          clientSecret: client_secret,
          confirmParams: {
            return_url: this.returnUrl,
          },
        });

        if (error) {
          this.handleStripeError(error, "error confirming payment");
        }

        // On success Stripe redirects to return_url.
      });
    } catch (error) {
      const message =
        "Failed to initialize payment form. Please try again later.";
      this.logAndPushError(message, error);
      this.stripeReady(); // Re-enable button if initialization fails
    }
  },

  // Switching between one-off and subscription changes card saving and the
  // CustomerSession, and Elements can't swap a CustomerSession in place.
  // ponytail: reloads the page rather than rebuilding Elements in place.
  updated() {
    if (this.el.dataset.setupFutureUsage !== this.setupFutureUsage) {
      return window.location.reload();
    }

    // Apple Pay and Google Pay show this amount on their sheets.
    const amount = Number(this.el.dataset.amount);
    if (this.mode === "payment" && amount !== this.amount) {
      this.amount = amount;
      this.elements.update({ amount });
    }
  },

  // Elements starts before the PaymentIntent or SetupIntent exists, and must
  // match what the server creates when the customer pays. One that saves a
  // card for later charges takes only cards.
  intentOptions() {
    if (this.mode === "setup") {
      return { mode: "setup", currency: "eur", paymentMethodTypes: ["card"] };
    }

    const options = { mode: "payment", amount: this.amount, currency: "eur" };
    if (this.setupFutureUsage) {
      options.setupFutureUsage = this.setupFutureUsage;
      options.paymentMethodTypes = ["card"];
    }
    return options;
  },

  // The Payment Element shows validation errors itself, but not a declined
  // card; Stripe's card_error message is written for the customer.
  handleStripeError(error, message) {
    if (error.type === "card_error") {
      this.stripeErrorMessage.textContent = error.message;
    } else if (error.type !== "validation_error") {
      this.logAndPushError(message, error);
    }

    this.stripeReady(); // Re-enable button after payment error
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
    this.button.removeAttribute("aria-busy");
    this.liveSocket.execJS(this.el, this.stripeReadyJS);
  },

  // The form's .phx-submit-loading ends when the server acks "pay", but
  // confirmPayment (and any 3DS challenge) runs long after, so the button
  // carries its own busy state to keep the spinner up until Stripe settles.
  stripeLoading() {
    this.button.setAttribute("aria-busy", "true");
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
   *                           outline 2px solid with 2px offset, in primary --
   *                           daisyUI draws that outline in base-content, base.css
   *                           overrides every focus ring to the brand green
   *   - invalid: border-color and focus outline flip to --color-error
   *   - input-lg: 48px tall, 18px font, 12px horizontal padding
   *
   * The payment-method tabs mirror the `radio-card` input instead: base-300
   * frame, primary frame over a 5% primary wash once selected.
   */
  buildAppearance() {
    const css = getComputedStyle(document.documentElement);
    const v = (name, fallback = "") =>
      css.getPropertyValue(name).trim() || fallback;

    // Stripe's colour variables only accept hex, rgb() or hsl() and silently
    // drop our oklch() tokens, so paint each one to a canvas pixel to get sRGB.
    const ctx = document
      .createElement("canvas")
      .getContext("2d", { willReadFrequently: true });
    const rgb = (name) => {
      ctx.fillStyle = v(name);
      ctx.fillRect(0, 0, 1, 1);
      const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
      return `rgb(${r}, ${g}, ${b})`;
    };

    const baseContent = rgb("--color-base-content");
    const base100 = rgb("--color-base-100");
    const primary = rgb("--color-primary");
    const error = rgb("--color-error");
    const base300 = rgb("--color-base-300");

    const subtleBorder = `color-mix(in oklab, ${baseContent} 20%, transparent)`;
    // Checkboxes carry a heavier hairline than inputs -- see `.checkbox` in forms.css.
    const checkboxBorder = `color-mix(in oklab, ${baseContent} 55%, transparent)`;

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
        // Our form stacks fields with `space-y-6`.
        gridRowSpacing: "24px",
      },
      rules: {
        ".Input": {
          backgroundColor: base100,
          border: `1px solid ${subtleBorder}`,
          boxShadow: "none",
          fontSize: "18px",
          fontWeight: "400",
          lineHeight: "27px",
          // Stripe's inputs are border-box: 2 × 9.5px + 27px line-height + 2px border = 48px (input-lg).
          padding: "9.5px 12px",
        },
        ".Input::placeholder": {
          color: `color-mix(in oklab, ${baseContent} 50%, transparent)`,
        },
        ".Input:focus": {
          backgroundColor: base100,
          border: `1px solid ${baseContent}`,
          outline: `2px solid ${primary}`,
          outlineOffset: "2px",
          boxShadow: "none",
        },
        ".Input--invalid": {
          backgroundColor: base100,
          border: `1px solid ${error}`,
          boxShadow: "none",
          // Stripe tints invalid text with colorDanger; `.input-error` only reddens the frame.
          color: baseContent,
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
          marginBottom: "4px",
        },
        ".Tab": {
          backgroundColor: base100,
          border: `1px solid ${base300}`,
          boxShadow: "none",
          color: baseContent,
        },
        ".Tab:hover": {
          backgroundColor: base100,
          border: `1px solid ${primary}`,
          boxShadow: "none",
          color: baseContent,
        },
        ".Tab--selected": {
          backgroundColor: `color-mix(in oklab, ${primary} 5%, ${base100})`,
          border: `1px solid ${primary}`,
          boxShadow: "none",
          color: baseContent,
        },
        ".Tab--selected:focus": {
          backgroundColor: `color-mix(in oklab, ${primary} 5%, ${base100})`,
          border: `1px solid ${primary}`,
          outline: `2px solid ${primary}`,
          outlineOffset: "2px",
          boxShadow: "none",
          color: baseContent,
        },
        // The flat theme fills a selected tab with colorPrimary and lightens its
        // label and icon to match; our tint is light, so they stay dark.
        ".TabLabel--selected": {
          color: baseContent,
        },
        ".TabIcon--selected": {
          fill: baseContent,
        },
        // Matches the recurring-charge note below it (`text-sm leading-relaxed text-base-content/80`).
        ".TermsText": {
          color: `color-mix(in oklab, ${baseContent} 80%, transparent)`,
          fontSize: "14px",
          fontWeight: "400",
          lineHeight: "22.75px",
        },
        ".CheckboxInput": {
          backgroundColor: base100,
          border: `1px solid ${checkboxBorder}`,
          borderRadius: "0",
          boxShadow: "none",
        },
        ".CheckboxInput--checked": {
          backgroundColor: primary,
          border: `1px solid ${primary}`,
          borderRadius: "0",
          boxShadow: "none",
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

/**
 * Click-to-zoom photo gallery (PhotoSwipe 5).
 *
 * Markup contract: the hook element wraps one <a> per photo, each linking to
 * the full-size image and carrying data-pswp-width/height. Those dimensions
 * must match the served image exactly or PhotoSwipe's zoom maths goes wrong —
 * the page builds both URL and attributes from the same numbers.
 */
Hooks.PhotoGallery = {
  mounted() {
    // Passing pswpModule as a value rather than a dynamic import keeps
    // everything in the single esbuild bundle — no runtime chunk fetch.
    this.lightbox = new PhotoSwipeLightbox({
      gallery: this.el,
      children: "a[data-pswp-width]",
      pswpModule: PhotoSwipe,
    });

    // A mouse click leaves the thumbnail focused, so Escape rings it on close.
    // Keyboard activation has detail 0 and keeps PhotoSwipe's focus round trip.
    this.el.addEventListener(
      "click",
      (e) => e.detail && document.activeElement?.blur(),
    );

    // Credit line. PhotoSwipe has no caption of its own, and the plugin that
    // adds one isn't worth a second vendored file for this. It clones the
    // thumbnail's figcaption, photographer link included, so there's one
    // source of truth.
    this.lightbox.on("uiRegister", () => {
      this.lightbox.pswp.ui.registerElement({
        name: "credit",
        appendTo: "root",
        onInit: (el, pswp) => {
          const render = () => {
            const caption = pswp.currSlide?.data?.element
              ?.closest("figure")
              ?.querySelector("figcaption");
            el.replaceChildren(...(caption?.cloneNode(true).childNodes ?? []));
          };
          pswp.on("change", render);
          render();
        },
      });
    });

    this.lightbox.init();
  },

  destroyed() {
    this.lightbox.destroy();
  },
};

/**
 * Dismisses an info flash after a few seconds by running its own phx-click
 * (clear-flash + hide), so a timed dismissal and a click look identical.
 * The countdown pauses while the toast is hovered or holds keyboard focus,
 * and restarts in full afterwards. Errors never get this hook: they stay
 * until the user dismisses them.
 */
const FLASH_DISMISS_MS = 5000;

Hooks.AutoDismissFlash = {
  mounted() {
    this.pause = () => clearTimeout(this.timer);
    this.resume = () => this.start();

    this.el.addEventListener("mouseenter", this.pause);
    this.el.addEventListener("focusin", this.pause);
    this.el.addEventListener("mouseleave", this.resume);
    this.el.addEventListener("focusout", this.resume);

    this.start();
  },

  // A new message patched into the same toast gets a full countdown.
  updated() {
    this.start();
  },

  start() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.liveSocket.execJS(this.el, this.el.getAttribute("phx-click"));
    }, FLASH_DISMISS_MS);
  },

  destroyed() {
    clearTimeout(this.timer);
  },
};

/**
 * Follows the link inside the hook element whose `data-arrow-key` matches the
 * pressed arrow key. Clicking the link keeps LiveView's own navigation.
 */
Hooks.ArrowKeyNav = {
  mounted() {
    this.onKeydown = (e) => {
      if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      if (
        e.target instanceof HTMLElement &&
        e.target.closest("input, textarea, select, [contenteditable]")
      )
        return;

      const link = this.el.querySelector(`a[data-arrow-key="${e.key}"]`);
      if (!(link instanceof HTMLElement)) return;

      e.preventDefault();
      link.click();
    };

    window.addEventListener("keydown", this.onKeydown);
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown);
  },
};

/**
 * Scrolls a sideways list so its `aria-current` item is in view, such as the
 * Overview's day strip opened on a day further out. Only on mount: a tapped
 * item is already in view.
 */
Hooks.ScrollToCurrent = {
  mounted() {
    const current = this.el.querySelector("[aria-current]")?.closest("li");
    if (!(current instanceof HTMLElement)) return;

    // scrollLeft rather than scrollIntoView, which can also scroll the page.
    this.el.scrollLeft =
      current.offsetLeft - (this.el.clientWidth - current.offsetWidth) / 2;
  },
};

/**
 * On the admin layout. Clears new-order notifications and the app icon badge
 * whenever the admin comes into view.
 */
Hooks.AdminApp = {
  mounted() {
    this.onVisible = () => {
      if (document.visibilityState === "visible") clearOrderAlerts();
    };
    document.addEventListener("visibilitychange", this.onVisible);
    this.onVisible();
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisible);
  },
};

/**
 * The account page's "New order notifications" switch for this device. Its
 * state lives in the browser, so the hook reads it and sets `data-state`
 * (checking, on, off, denied, unsupported, error), which picks the help text.
 * The element is phx-update="ignore", so patches leave the switch alone.
 */
Hooks.PushToggle = {
  async mounted() {
    this.input = /** @type {HTMLInputElement} */ (
      this.el.querySelector("input[role=switch]")
    );
    this.input.addEventListener("change", () => this.onChange());

    if (!pushSupported()) return this.setState("unsupported");
    if (Notification.permission === "denied") return this.setState("denied");

    const subscription = await resyncSubscription(this);
    this.setState(subscription ? "on" : "off");
  },

  async onChange() {
    this.input.disabled = true;

    if (this.input.checked) {
      this.setState(
        await subscribeDevice(this, this.el.dataset.vapidPublicKey),
      );
    } else {
      await unsubscribeDevice(this).catch(() => {});
      const subscription = await currentSubscription().catch(() => null);
      this.setState(subscription ? "on" : "off");
    }
  },

  /** @param {string} state */
  setState(state) {
    this.js().setAttribute(this.el, "data-state", state);
    this.input.checked = state === "on";
    this.input.disabled = !["on", "off", "error"].includes(state);
  },
};

/**
 * The Overview card offering order notifications, shown once in the installed
 * app before it has asked for permission. Either button hides it for good on
 * this device; the account page's switch is there after that.
 */
const PUSH_NUDGE_DISMISSED_KEY = "eden:push-nudge-dismissed";

Hooks.PushNudge = {
  mounted() {
    // The Overview is where the installed app opens, so every launch re-saves
    // this device's subscription.
    if (pushSupported()) resyncSubscription(this);

    const installed =
      window.matchMedia("(display-mode: standalone)").matches ||
      /** @type {any} */ (navigator).standalone === true;

    if (
      !installed ||
      !pushSupported() ||
      Notification.permission !== "default" ||
      this.dismissed()
    )
      return;

    this.js().removeAttribute(this.el, "hidden");

    this.el
      .querySelector("[data-push-nudge=dismiss]")
      ?.addEventListener("click", () => this.dismiss());

    this.el
      .querySelector("[data-push-nudge=enable]")
      ?.addEventListener("click", () => {
        subscribeDevice(this, this.el.dataset.vapidPublicKey);
        this.dismiss();
      });
  },

  dismissed() {
    try {
      return localStorage.getItem(PUSH_NUDGE_DISMISSED_KEY) !== null;
    } catch {
      return false;
    }
  },

  dismiss() {
    try {
      localStorage.setItem(PUSH_NUDGE_DISMISSED_KEY, "1");
    } catch {
      // Without storage the card simply comes back next time.
    }
    this.js().setAttribute(this.el, "hidden", "");
  },
};

/**
 * Fee graph on an admin delivery option. The server sends the fee and costs
 * every tenth of a km in data-points; this only moves the cursor and fills in
 * the readout for the whole km nearest the pointer or on the slider.
 */
Hooks.FeeExplorer = {
  mounted() {
    this.km = 5;
    this.svg = this.el.querySelector("svg");
    this.slider = this.el.querySelector("input[type=range]");

    this.slider.addEventListener("input", () =>
      this.show(Number(this.slider.value)),
    );
    this.svg.addEventListener("pointermove", (event) =>
      this.show(this.kmAt(event)),
    );
    this.svg.addEventListener("pointerdown", (event) =>
      this.show(this.kmAt(event)),
    );

    this.load();
  },

  // A re-render resets the cursor, so put it back where it was.
  updated() {
    this.load();
  },

  load() {
    this.points = JSON.parse(this.el.dataset.points);
    this.plot = JSON.parse(this.el.dataset.plot);
    this.stepsPerKm = Number(this.el.dataset.stepsPerKm);
    const lang = document.documentElement.lang || undefined;
    this.money = new Intl.NumberFormat(lang, {
      style: "currency",
      currency: "EUR",
    });
    this.distance = new Intl.NumberFormat(lang);
    this.show(Math.min(this.km, this.plot.maxKm));
  },

  kmAt(event) {
    const { left, right, maxKm } = this.plot;
    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(
      this.svg.getScreenCTM().inverse(),
    );
    const km = ((point.x - left) / (right - left)) * maxKm;
    return Math.min(Math.max(km, 0), maxKm);
  },

  show(km) {
    this.km = Math.round(km);
    const point = this.points[this.km * this.stepsPerKm];
    this.slider.value = this.km;

    const { left, right, top, bottom, maxKm, topValue } = this.plot;
    const x = left + (this.km / maxKm) * (right - left);
    const y = (value) => bottom - (value / topValue) * (bottom - top);

    const cursor = this.el.querySelector("[data-cursor]");
    cursor.setAttribute("x1", x);
    cursor.setAttribute("x2", x);

    for (const dot of this.el.querySelectorAll("[data-dot]")) {
      const value = point[dot.dataset.dot];
      dot.toggleAttribute("hidden", value == null);
      if (value != null) {
        dot.setAttribute("cx", x);
        dot.setAttribute("cy", y(value));
      }
    }

    this.fill("km", `${this.distance.format(this.km)} km`);
    this.fill(
      "fee",
      point.fee == null
        ? this.el.dataset.notDelivered
        : this.money.format(point.fee),
    );
    for (const key of ["now", "car", "fuel"]) {
      this.fill(key, point[key] == null ? "–" : this.money.format(point[key]));
    }
  },

  fill(key, text) {
    const el = this.el.querySelector(`[data-value=${key}]`);
    if (el) el.textContent = text;
  },
};

export default Hooks;
