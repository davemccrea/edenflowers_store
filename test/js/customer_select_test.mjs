import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const source = readFileSync(
  new URL("../../assets/js/customer_select.js", import.meta.url),
  "utf8",
)
  .replace(/^import [^;]*;\n/m, "")
  .replace("export const customerLiveSelect", "globalThis.customerLiveSelect");

// LiveSelect's own hook, as far as this contract goes: the server's "select"
// event sets the selection and writes current_text into the box.
const liveSelect = {
  LiveSelect: {
    mounted() {
      this.handleEvent("select", ({ selection, current_text }) => {
        this.selection = selection;
        if (current_text != null) this.setInputValue(current_text);
      });
    },
    updated() {},
    setInputValue(value) {
      this.textInput().value = value;
    },
  },
};

const mountHook = () => {
  const context = { liveSelect };
  vm.runInNewContext(source, context);

  const input = {
    type: "text",
    value: "",
    placeholder: "",
    setAttribute() {},
    removeAttribute() {},
  };
  const listeners = {};
  const handlers = [];
  const hook = {
    ...context.customerLiveSelect,
    selection: [],
    el: {
      id: "customer-select",
      addEventListener: (name, callback) => (listeners[name] = callback),
      querySelector: (selector) =>
        selector.startsWith("input") ? input : null,
    },
    textInput: () => input,
    handleEvent: (name, callback) =>
      name === "select" && handlers.push(callback),
  };
  hook.mounted();

  const select = (payload) =>
    handlers.forEach((handler) =>
      handler({ id: "customer-select", ...payload }),
    );
  const blur = () => listeners.focusout({ target: input });
  return { input, select, blur };
};

test("a typed search stays in the box when focus leaves without a pick", () => {
  const { input, select, blur } = mountHook();
  input.value = "anna";
  blur();
  select({ selection: [], current_text: "" });
  assert.equal(input.value, "anna");
});

test("a picked customer's label still replaces the search", () => {
  const { input, select, blur } = mountHook();
  input.value = "anna";
  blur();
  select({
    selection: [{ label: "Anna · anna@example.com", value: "1" }],
    current_text: "Anna · anna@example.com",
  });
  assert.equal(input.value, "Anna · anna@example.com");
});

test("clearing a picked customer empties the box", () => {
  const { input, select, blur } = mountHook();
  select({ selection: [{ label: "Anna", value: "1" }], current_text: "Anna" });
  blur();
  select({ selection: [], current_text: "" });
  assert.equal(input.value, "");
});
