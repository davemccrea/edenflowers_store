import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL(
    "../deps/live_select/priv/static/live_select.min.js",
    import.meta.url,
  ),
  "utf8",
);
const { default: hooks } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
);

test("LiveSelect consumes Enter so customer search cannot submit the order", () => {
  const input = {};
  const events = [];
  const hook = {
    ...hooks.LiveSelect,
    el: {
      dataset: { debounce: "300" },
      querySelector: (selector) =>
        selector === "input[type=text]" ? input : null,
      querySelectorAll: () => [],
    },
    pushEventTo: (_target, event, params) => events.push([event, params]),
  };
  hook.attachDomEventHandlers();
  let prevented = false;
  input.onkeydown({
    code: "Enter",
    preventDefault: () => {
      prevented = true;
    },
  });
  assert.equal(prevented, true);
  assert.deepEqual(events, [["keydown", { key: "Enter" }]]);
});

const appSource = await readFile(
  new URL("../assets/js/app.js", import.meta.url),
  "utf8",
);
const syncCustomerCombobox = new Function(
  `${appSource.slice(appSource.indexOf("const syncCustomerCombobox"), appSource.indexOf("const customerLiveSelect"))}; return syncCustomerCombobox;`,
)();

test("combobox selection follows LiveSelect state while the input contains a different search", () => {
  const element = () => ({
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    removeAttribute(name) {
      delete this.attributes[name];
    },
  });
  const input = { ...element(), value: "Another customer" };
  const option = (selected, active) => ({
    ...element(),
    textContent: "Another customer",
    querySelector: () => ({ dataset: { selected: String(selected) } }),
    classList: { contains: (name) => active && name === "menu-active" },
  });
  const selected = option(true, false);
  const searching = option(false, true);
  const list = {
    ...element(),
    querySelectorAll: () =>
      [selected, searching].map((firstElementChild) => ({
        ...element(),
        firstElementChild,
      })),
  };
  const el = {
    id: "customer-select",
    querySelector: (selector) => (selector === "ul" ? list : input),
  };
  syncCustomerCombobox(el);
  assert.equal(selected.attributes["aria-selected"], "true");
  assert.equal(searching.attributes["aria-selected"], "false");
  assert.equal(input.attributes["aria-activedescendant"], searching.id);
  assert.equal(input.attributes["aria-controls"], list.id);
  assert.equal(input.attributes["aria-expanded"], "true");
  el.querySelector = (selector) => (selector === "ul" ? null : input);
  syncCustomerCombobox(el);
  assert.equal(input.attributes["aria-expanded"], "false");
  assert.equal(input.attributes["aria-activedescendant"], undefined);
  assert.equal(input.attributes["aria-controls"], undefined);
});
