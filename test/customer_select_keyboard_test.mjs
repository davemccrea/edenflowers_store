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
const customerLiveSelect = new Function(
  "liveSelect",
  "syncCustomerCombobox",
  `${appSource.slice(appSource.indexOf("const customerLiveSelect"), appSource.indexOf("const csrfToken"))}; return customerLiveSelect;`,
)(hooks, syncCustomerCombobox);

test("native focus/click shows the selected customer as context without replacing search or selection behavior", async () => {
  const label = "Ada Lovelace · ada@example.com";
  const input = {
    value: label,
    setAttribute() {},
    removeAttribute() {},
  };
  const callbacks = {};
  const events = [];
  const selections = [];
  const hook = {
    ...customerLiveSelect,
    el: {
      id: "customer-select",
      dataset: { debounce: "0", updateMinLen: "0" },
      querySelector: (selector) => {
        if (selector === "input.single-mode") {
          return {
            dispatchEvent: (event) => {
              assert.equal(event.type, "input");
              selections.push(hook.selection);
            },
          };
        }
        return selector.startsWith("input") ? input : null;
      },
      querySelectorAll: () => [],
    },
    handleEvent: (event, callback) => {
      (callbacks[event] ??= []).push(callback);
    },
    pushEventTo: (_target, event, params) => events.push([event, params]),
    pushEvent: (event, params) => events.push([event, params]),
  };
  hook.mounted();
  assert.equal(input.placeholder, label);
  const selection = [{ label, value: "ada" }];
  const send = (params) =>
    callbacks.select.forEach((callback) =>
      callback({ id: hook.el.id, mode: "single", selection, ...params }),
    );
  send({ current_text: label, input_event: true });
  for (const event of ["focus", "click"]) {
    send({ current_text: "", input_event: false });
    assert.equal(
      input.value || input.placeholder,
      label,
      `${event} must not blank the selected customer`,
    );
    assert.equal(
      input.value,
      "",
      `${event} leaves the native search empty, ready for typing`,
    );
  }
  input.value = "Grace";
  input.oninput({ target: input });
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.ok(
    events.some(
      ([event, params]) => event === "change" && params.text === "Grace",
    ),
  );
  send({ current_text: "Grace", input_event: false });
  assert.equal(
    input.value,
    "Grace",
    "native current query is not replaced by the selected label",
  );
  input.placeholder = ""; // LiveView patches the server-rendered input attributes.
  hook.updated();
  assert.equal(input.placeholder, label);
  assert.equal(input.value, "Grace", "patches do not change typed text");
  send({ current_text: label }); // blur restores the committed selection
  assert.equal(input.value, label);
  input.value = "";
  input.oninput({ target: input });
  await new Promise((resolve) => setTimeout(resolve, 5));
  send({ current_text: "", input_event: false });
  assert.equal(input.value, "", "deleting the search text stays possible");
  send({ selection: [], current_text: "", input_event: true });
  assert.equal(input.value, "");
  assert.equal(input.placeholder, "", "clearing removes the selected context");
  assert.deepEqual(hook.selection, []);
  assert.deepEqual(
    selections,
    [selection, []],
    "focus/click must not change the form selection",
  );
  const replacement = [
    { label: "Grace Hopper · grace@example.com", value: "grace" },
  ];
  send({
    selection: replacement,
    current_text: replacement[0].label,
    input_event: true,
  });
  send({ selection: replacement, current_text: "", input_event: false });
  assert.equal(input.placeholder, replacement[0].label);
  assert.deepEqual(hook.selection, replacement);
  assert.deepEqual(selections, [selection, [], replacement]);
  hook.updated();
  let prevented = false;
  input.onkeydown({
    code: "Enter",
    preventDefault() {
      prevented = true;
    },
  });
  assert.equal(prevented, true);
});

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
    classList: { contains: (name) => active && name === "bg-primary" },
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
