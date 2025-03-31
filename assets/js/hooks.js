// @ts-check

export const Hooks = {};

Hooks.CharacterCount = {
  mounted() {
    const textarea = this.el.querySelector("textarea");
    // const charCountDisplay = this.el.querySelector("#gift-message-char-count");
    const charCountDisplay = this.el.querySelector("span");

    // Update character count on page load (in case there's initial text)
    updateCharCount();

    // Add event listeners for input events
    textarea.addEventListener("input", updateCharCount);

    function updateCharCount() {
      const count = textarea.value.length;
      charCountDisplay.textContent = `${count}/${textarea.maxLength}`;
    }
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
        "Attribute 'data-focusable-dates' is required and must not be empty."
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

Hooks.Scroll = {
  mounted() {
    this.handleEvent("scroll", ({ anchor }) => {
      if (anchor) {
        const element = document.getElementById(anchor);
        if (element) {
          element.scrollIntoView();
        }
      }
    });
  },
};

Hooks.PaymentElement = {
  mounted() {
    const button = document.getElementById("payment-button");
    if (!button) {
      console.error(`Element with id "payment-button" not found`);
      return;
    }

    // @ts-ignore
    const stripe = Stripe("pk_test_3gvP7KfmcinLf52LVqP6JstL00Rr9tIeXM");
    const clientSecret = this.el.getAttribute("data-client-secret");
    const elements = stripe.elements({ clientSecret, appearance: {} });
    const paymentElement = elements.create("payment", {
      layout: {
        type: "accordion",
        defaultCollapsed: false,
        radios: true,
        spacedAccordionItems: false,
      },
    });

    paymentElement.mount("#payment-element");

    paymentElement.on("ready", function () {
      button.removeAttribute("disabled");
    });
  },
};

Hooks.ProductSwiper = {
  mounted() {
    // @ts-ignore
    const swiper = new Swiper(".swiper", {
      direction: "horizontal",
      slidesPerView: 1.3,
      spaceBetween: 6,
      centeredSlides: true,
      centeredSlidesBounds: true,
      centerInsufficientSlides: true,

      keyboard: {
        enabled: true,
        onlyInViewport: true,
      },

      breakpoints: {
        // sm
        640: {
          slidesPerView: 2,
          centeredSlides: false,
        },
        // md
        768: {
          slidesPerView: 3,
          centeredSlides: false,
        },
        // lg
        1024: {
          slidesPerView: 4,
          centeredSlides: false,
        },
      },

      scrollbar: {
        el: ".swiper-scrollbar",
        draggable: true,
        dragSize: "auto",
        snapOnRelease: true,
      },
    });
  },
};

export default Hooks;
