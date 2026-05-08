// @ts-check

export const Hooks = {};

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
  mounted() {
    // Focus on the first form element when the page loads (step 1)
    requestAnimationFrame(() => {
      const firstForm = this.el.querySelector('[id$="-form-1"]');
      if (firstForm) {
        const firstInput = firstForm.querySelector(
          'input:not([type="hidden"]), textarea, select, button[type="submit"]'
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
          'input:not([type="hidden"]), textarea, select, button[type="submit"]'
        );
        if (firstInput) {
          /** @type {HTMLElement} */ (firstInput).focus({ preventScroll: true });
        }
      });
    });
  },
};

/**
 * Navigate the calendar with the keyboard without a round trip to the server for each key press.
 * If the user tries to navigate to a date outside the visible month then the keydown event is
 * forwarded to the server and the server re-renders the view.
 */
Hooks.CalendarHook = {
  mounted() {
    // Validate required elements and attributes
    if (!this.validateRequirements()) return;

    // Set initial tab index
    this.setTabIndex(this.viewDate);

    this.calendarGrid.addEventListener("keydown", (event) => {
      const key = event.key;
      const keys = {
        ArrowUp: "data-key-arrow-up",
        ArrowDown: "data-key-arrow-down",
        ArrowLeft: "data-key-arrow-left",
        ArrowRight: "data-key-arrow-right",
        Home: "data-key-home",
        End: "data-key-end",
        PageUp: "data-key-page-up",
        PageDown: "data-key-page-down",
      };

      if (key in keys) {
        event.preventDefault();
        this.handleKeyDown(key, keys[key]);
      }
    });
  },

  updated() {
    this.focusableDates = this.getFocusableDates();
    this.viewDate = this.getViewDate();
    this.setTabIndex(this.viewDate);
  },

  /**
   * Handles the keydown event for the calendar grid.
   * @example
   * handleKeyDown("ArrowUp", "data-key-arrow-up");
   * @param {String} key - The key pressed by the user.
   * @param {String} attribute - The attribute associated with the key.
   * @returns {void}
   */
  handleKeyDown(key, attribute) {
    const viewDateEl = this.getElement(`calendar-day-${this.viewDate}`);
    if (!viewDateEl) return;

    const nextDate = viewDateEl.getAttribute(attribute);
    if (!nextDate) {
      this.error(`Attribute '${attribute}' is missing on view date element.`);
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
   * @example
   * serverFocus("ArrowUp");
   * @param {String} key - The key pressed by the user.
   * @returns {void}
   */
  serverFocus(key) {
    const payload = {
      key: key,
      viewDate: this.viewDate,
    };

    const callback = () => this.clientFocus(this.viewDate);

    this.pushEventTo(this.el, "keydown", payload, callback);
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
    if (!this.focusableDates || !this.focusableDates.length) {
      this.error(
        "Attribute 'data-focusable-dates' is required and must not be empty.",
      );
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
    if (!focusableDatesAttr) {
      this.error("Attribute 'data-focusable-dates' is required.");
      return [];
    }

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
    const v = (name, fallback = "") => css.getPropertyValue(name).trim() || fallback;

    const baseContent = v("--color-base-content", "#1f2937");
    const primary = v("--color-primary", "#0570de");
    const error = v("--color-error", "#dc2626");

    const subtleBorder = `color-mix(in oklab, ${baseContent} 20%, transparent)`;

    return {
      theme: "flat",
      variables: {
        colorPrimary: primary,
        colorBackground: v("--color-base-100", "#ffffff"),
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
          border: `1px solid ${subtleBorder}`,
          boxShadow: "none",
          fontSize: "18px",
          fontWeight: "400",
          lineHeight: "27px",
          // 10.5px vertical + 18px font + 27px line-height ≈ 48px (input-lg).
          padding: "10.5px 12px",
        },
        ".Input:focus": {
          border: `1px solid ${baseContent}`,
          outline: `2px solid ${baseContent}`,
          outlineOffset: "2px",
          boxShadow: "none",
        },
        ".Input--invalid": {
          border: `1px solid ${error}`,
          boxShadow: "none",
        },
        ".Input--invalid:focus": {
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

function toastVariantClasses(variant) {
  switch (variant) {
    case "success": return { border: "border-primary",   icon: "text-primary" };
    case "warning": return { border: "border-amber-500", icon: "text-amber-600" };
    case "error":
    case "danger":  return { border: "border-rose-500",  icon: "text-rose-500" };
    default:        return { border: "border-sky-400",   icon: "text-sky-500" };
  }
}

function toastIconSvg(variant) {
  switch (variant) {
    case "success":
      return `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>`;
    case "warning":
      return `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/></svg>`;
    case "error":
    case "danger":
      return `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>`;
    default:
      return `<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`;
  }
}

function createToast({ id, variant, message, duration, closable }) {
  const { border, icon: iconColor } = toastVariantClasses(variant);

  const div = document.createElement("div");
  if (id) div.id = id;
  div.className = `toast-item flex items-start gap-3 bg-base-100 shadow-sm border-l-2 ${border} rounded-r-sm px-4 py-3 min-w-[260px] max-w-xs`;
  div.setAttribute("role", "alert");

  const iconEl = document.createElement("span");
  iconEl.className = `shrink-0 mt-0.5 ${iconColor}`;
  iconEl.innerHTML = toastIconSvg(variant);
  div.appendChild(iconEl);

  const msgEl = document.createElement("p");
  msgEl.className = "text-sm text-base-content flex-1";
  msgEl.textContent = message;
  div.appendChild(msgEl);

  if (closable) {
    const btn = document.createElement("button");
    btn.className = "text-base-content/30 hover:text-base-content/60 ml-auto -mr-1 -mt-0.5 text-lg leading-none cursor-pointer";
    btn.setAttribute("aria-label", "Dismiss");
    btn.textContent = "×";
    btn.addEventListener("click", () => dismissToast(div));
    div.appendChild(btn);
  }

  if (duration > 0) {
    setTimeout(() => dismissToast(div), duration);
  }

  return div;
}

function dismissToast(el) {
  el.style.transition = "opacity 0.2s, transform 0.2s";
  el.style.opacity = "0";
  el.style.transform = "translateX(0.5rem)";
  setTimeout(() => el.remove(), 200);
}

Hooks.AlertHandler = {
  mounted() {
    this.handleEvent("toast:show", (toast) => {
      this.el.appendChild(createToast({
        id: `alert-${toast.id}`,
        variant: toast.variant,
        message: toast.message,
        duration: parseInt(toast.duration || "5000", 10),
        closable: toast.closable,
      }));
    });
  },

  disconnected() {
    if (document.getElementById("alert-disconnected")) return;
    this.el.appendChild(createToast({
      id: "alert-disconnected",
      variant: "warning",
      message: this.el.getAttribute("data-disconnected-message"),
      duration: 0,
      closable: false,
    }));
  },

  reconnected() {
    const el = document.getElementById("alert-disconnected");
    if (el) dismissToast(el);
  },
};

Hooks.FlashHandler = {
  mounted() {
    const container = document.getElementById("alert-group") || this.el;
    for (const flashEl of Array.from(this.el.querySelectorAll("[data-variant]"))) {
      container.appendChild(createToast({
        id: flashEl.id,
        variant: flashEl.dataset.variant,
        message: flashEl.dataset.message,
        duration: parseInt(flashEl.dataset.duration || "5000", 10),
        closable: flashEl.dataset.closable === "true",
      }));
    }
    this.pushEvent("lv:clear-flash", {});
  },

  disconnected() {
    // Alerts already moved to #alert-group; nothing to clean up
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
