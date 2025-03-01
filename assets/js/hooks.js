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

export default Hooks;
