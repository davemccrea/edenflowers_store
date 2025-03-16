// @ts-check

export const Hooks = {};

Hooks.Spinner = {
  mounted() {
    const element = this.el;
    const submitButton = element.querySelector(".submit-button");

    this.mutationObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (element.classList.contains("phx-submit-loading")) {
          submitButton.setAttribute("loading", "");
        } else {
          submitButton.removeAttribute("loading");
        }
      });
    });

    this.mutationObserver.observe(element, {
      attributes: true,
      attributeFilter: ["class"],
    });
  },
  destroyed() {
    this.mutationObserver.disconnect();
  },
};

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
  PHX_VALUE_DATE: "phx-value-date",
  DATA_VIEW_DATE: "data-view-date",

  mounted() {
    this.id = this.el.getAttribute("id");
    if (!this.id) {
      return this.error("Element must have an 'id' attribute.");
    }

    this.viewDate = this.getViewDate();
    if (!this.viewDate) {
      return this.error(`Attribute ${this.DATA_VIEW_DATE} is required.`);
    }

    this.focusableDates = this.getFocusableDates();
    if (!this.focusableDates || !this.focusableDates.length) {
      return this.error(
        "Attribute 'data-focusable-dates' is required and must not be empty."
      );
    }

    this.calendarGrid = this.el.querySelector(`#${this.id}-grid`);
    if (!this.calendarGrid) {
      return this.error(`Calendar grid with id '${this.id}-grid' not found.`);
    }

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
    this.focus = this.el.getAttribute("data-focus");
    this.viewDate = this.getViewDate();
    this.focusableDates = this.getFocusableDates();
    this.setTabIndex(this.viewDate);

    if (this.el.hasAttribute("data-should-focus")) {
      this.clientFocus(this.viewDate);
    }
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
    const viewDateEl = document.querySelector(
      `[${this.PHX_VALUE_DATE}="${this.viewDate}"]`
    );

    if (!viewDateEl) {
      return this.error(
        `View date element with ${this.PHX_VALUE_DATE}="${this.viewDate}" not found.`
      );
    }

    const nextDate = viewDateEl.getAttribute(attribute);

    if (!nextDate) {
      return this.error(
        `Attribute '${attribute}' is missing on view date element.`
      );
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
      return this.error("Cannot focus on null date.");
    }

    const dateEl = document.querySelector(`[${this.PHX_VALUE_DATE}="${date}"]`);
    if (dateEl) {
      /** @type {HTMLElement} */ (dateEl).focus();
    } else {
      this.error(`Element with ${this.PHX_VALUE_DATE}="${date}" not found.`);
    }
  },

  /**
   * Used when the focus is moved to a date that is not focusable by the client.
   * @example
   * serverFocus("ArrowUp");
   * @param {String} key - The key pressed by the user.
   * @returns {void}
   */
  serverFocus(key) {
    this.pushEventTo(this.el, "keydown", {
      key: key,
      viewDate: this.viewDate,
    });
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
    const viewDateEl = document.querySelector(
      `[${this.PHX_VALUE_DATE}="${this.viewDate}"]`
    );
    if (viewDateEl) {
      viewDateEl.setAttribute("tabindex", "-1");
    }

    // Set focus on next date
    if (nextDate) {
      const nextDateEl = document.querySelector(
        `[${this.PHX_VALUE_DATE}="${nextDate}"]`
      );
      if (nextDateEl) {
        nextDateEl.setAttribute("tabindex", "0");
      }
    }
  },

  //
  // Utility Methods
  //

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

    for (let i = 0; i < this.focusableDates.length; i++) {
      if (this.focusableDates[i] == date) {
        return true;
      }
    }

    return false;
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
    return this.el.getAttribute(this.DATA_VIEW_DATE);
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

export default Hooks;
