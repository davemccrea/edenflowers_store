// @ts-check

export const Hooks = {};

const PHX_VALUE_DATE = "phx-value-date";

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
  mounted() {
    this.id = this.el.getAttribute("id");
    this.currentDate = this.getCurrentDate();
    this.focusableDates = this.getFocusableDates();
    this.setTabIndex(this.currentDate);

    this.el
      .querySelector(`#${this.id}-grid`)
      .addEventListener("keydown", (event) => {
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

    this.handleEvent("update-client", ({ focus = true }) => {
      this.currentDate = this.getCurrentDate();
      this.focusableDates = this.getFocusableDates();
      this.setTabIndex(this.currentDate);
      if (focus) {
        this.clientFocus(this.currentDate);
      }
    });
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
    const currentDateEl = document.querySelector(
      `[${PHX_VALUE_DATE}="${this.currentDate}"]`
    );

    if (!currentDateEl) {
      return this.pushError(`Attribute '${PHX_VALUE_DATE}' is required.`);
    }

    const nextDate = currentDateEl.getAttribute(attribute);

    if (!nextDate) {
      return this.pushError(`Attribute '${attribute}' is required.`);
    }

    // This part is important - check if the next date is focusable by the client.
    // If not focusable the keydown event is forwarded to and handled on the server.
    if (!this.isClientFocusable(nextDate)) {
      return this.serverFocus(key);
    }

    this.clientFocus(nextDate);
    this.setTabIndex(nextDate);
    this.currentDate = nextDate;
  },

  /**
   * Moves focus to the given date.
   * @example
   * clientFocus("2023-06-01");
   * @param {String} date - The date to move the focus to.
   * @returns {void}
   */
  clientFocus(date) {
    // @ts-ignore
    document.querySelector(`[${PHX_VALUE_DATE}="${date}"]`).focus();
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
      currentDate: this.currentDate,
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
    const currentDateEl = document.querySelector(
      `[${PHX_VALUE_DATE}="${this.currentDate}"]`
    );
    if (currentDateEl) {
      // @ts-ignore
      currentDateEl.tabIndex = "-1";
    }

    const nextDateEl = document.querySelector(
      `[${PHX_VALUE_DATE}="${nextDate}"]`
    );
    if (nextDateEl) {
      // @ts-ignore
      nextDateEl.tabIndex = "0";
    }
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

    for (let i = 0; i < this.focusableDates.length; i++) {
      if (this.focusableDates[i] == date) {
        return true;
      }
    }

    return false;
  },

  getFocusableDates() {
    return JSON.parse(this.el.getAttribute("data-focusable-dates"));
  },

  getCurrentDate() {
    return this.el.getAttribute("data-view-date");
  },

  /**
   * Logs error message to the console and forwards error to the server.
   * @example
   * pushError("Attribute 'data-focusable-dates' is required.");
   * @param {String} message - The error message to send to the server.
   * @returns {void}
   */
  pushError(message) {
    console.error(message);
    this.pushEventTo(this.el, "client-error", { message: message });
  },
};

export default Hooks;
