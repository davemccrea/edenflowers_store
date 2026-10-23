import liveSelect from "live_select";

// LiveSelect 1.7 supplies keyboard handling but no combobox ARIA semantics.
const syncCustomerCombobox = (el, selection) => {
  if (el.id !== "customer-select") return;
  const input = el.querySelector('input[type="text"]');
  // Native focus clears the search; keep the committed selection visible as context.
  input.placeholder = selection ? (selection[0]?.label ?? "") : input.value;
  const list = el.querySelector("ul");
  input.setAttribute("role", "combobox");
  input.setAttribute("aria-autocomplete", "list");
  input.setAttribute("aria-expanded", String(!!list));
  input.setAttribute("aria-describedby", "customer-search-help");
  input.removeAttribute("aria-activedescendant");
  input.removeAttribute("aria-controls");
  if (!list) return;
  list.id = `${el.id}-options`;
  list.setAttribute("role", "listbox");
  input.setAttribute("aria-controls", list.id);
  list.querySelectorAll("li").forEach((item, index) => {
    item.setAttribute("role", "presentation");
    const option = item.firstElementChild;
    option.id = `${list.id}-${index}`;
    option.setAttribute("role", "option");
    option.setAttribute(
      "aria-selected",
      option.querySelector("[data-selected]").dataset.selected,
    );
    if (option.classList.contains("bg-primary")) {
      input.setAttribute("aria-activedescendant", option.id);
    }
  });
};

export const customerLiveSelect = {
  ...liveSelect.LiveSelect,
  mounted() {
    liveSelect.LiveSelect.mounted.call(this);
    this.handleEvent("select", ({ id, selection }) => {
      if (id === this.el.id) syncCustomerCombobox(this.el, selection);
    });
    syncCustomerCombobox(this.el, this.selection);
  },
  updated() {
    liveSelect.LiveSelect.updated.call(this);
    syncCustomerCombobox(this.el, this.selection);
  },
};
