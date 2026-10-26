// Native <details> owns the open state, including across LiveView patches.
export default {
  mounted() {
    this.button = this.el.querySelector("[data-faq-section-toggle]");
    this.onClick = () => {
      const items = [...this.el.querySelectorAll("details")];
      const open = !items.every((item) => item.open);
      items.forEach((item) => (item.open = open));
      this.sync();
    };
    this.onToggle = () => this.sync();

    this.button.addEventListener("click", this.onClick);
    // The native toggle event does not bubble.
    this.el.addEventListener("toggle", this.onToggle, true);
    this.sync();
  },

  updated() {
    this.sync();
  },

  destroyed() {
    this.button.removeEventListener("click", this.onClick);
    this.el.removeEventListener("toggle", this.onToggle, true);
  },

  sync() {
    const items = [...this.el.querySelectorAll("details")];
    const open = items.length > 0 && items.every((item) => item.open);
    this.button.setAttribute("aria-expanded", String(open));
    this.button.parentElement.classList.toggle("collapse-open", open);
  },
};
