import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const picker = readFileSync(
  new URL("../../assets/js/dev_element_picker.js", import.meta.url),
  "utf8",
).replace(/^import .*;\n/, "");

const fixture = () => {
  const listeners = new Map();
  const overlays = [];
  const copied = [];
  const listen = (name, callback) => {
    const callbacks = listeners.get(name) || [];
    callbacks.push(callback);
    listeners.set(name, callbacks);
  };
  const element = (tag, parentElement = null) => ({
    tagName: tag.toUpperCase(),
    id: "",
    classList: [],
    getAttribute: () => null,
    style: {},
    parentElement,
    isConnected: true,
    closest: () => null,
    getBoundingClientRect: () => ({
      top: 40,
      left: 20,
      width: 80,
      height: 30,
      bottom: 70,
    }),
    append(...nodes) {
      for (const node of nodes) node.parentNode = this;
    },
  });
  const body = element("body");
  const parent = element("button", body);
  const child = element("span", parent);
  const document = {
    body,
    querySelector: () => parent,
    addEventListener: listen,
    createElement: (tag) => {
      const node = element(tag);
      overlays.push(node);
      return node;
    },
  };
  vm.runInNewContext(picker, {
    document,
    window: { addEventListener: listen },
    navigator: { clipboard: { writeText: async (text) => copied.push(text) } },
    findHeexSource: () => null,
    elementReference: (node) => node.tagName,
    innerWidth: 1000,
    innerHeight: 800,
    setTimeout: () => 1,
    clearTimeout: () => {},
    console,
  });
  const fire = async (name, properties = {}) => {
    const event = {
      target: child,
      altKey: true,
      preventDefault() {
        this.defaultPrevented = true;
      },
      stopPropagation() {
        this.propagationStopped = true;
      },
      ...properties,
    };
    for (const callback of listeners.get(name) || []) await callback(event);
    return event;
  };
  return { fire, copied, overlays, parent, child, body, listeners };
};

test("copies the exact clicked element, including an unannotated child", async () => {
  const { fire, copied } = fixture();
  const event = await fire("click");
  assert.deepEqual(copied, ["SPAN"]);
  assert.ok(event.defaultPrevented);
  assert.ok(event.propagationStopped);
});

test("Option+arrows select ancestors and return along the original child path", async () => {
  const { fire, copied, overlays } = fixture();
  await fire("mousemove");
  await fire("keydown", { key: "ArrowUp" });
  assert.match(overlays[1].textContent, /^button/);
  await fire("mousemove");
  assert.match(overlays[1].textContent, /^button/);
  await fire("keydown", { key: "ArrowDown" });
  assert.match(overlays[1].textContent, /^span/);
  await fire("keydown", { key: "ArrowUp" });
  await fire("click");
  assert.deepEqual(copied, ["BUTTON"]);
  assert.equal(overlays[2].textContent, "✓ Copied");
  assert.match(overlays[1].textContent, /^button/);
});

test("popup keeps element identity and controls terse", async () => {
  const { fire, overlays, child } = fixture();
  child.id = "add-to-cart";
  child.classList = ["unnecessary-class"];
  await fire("mousemove");
  assert.equal(overlays[1].textContent, "span#add-to-cart · no source");
  assert.equal(overlays[2].textContent, "⌥↑ parent · ⌥↓ child · ⌥click copy");
});

test("SVG internals select the SVG itself, including on direct click", async () => {
  const { fire, copied, overlays, parent, child } = fixture();
  parent.tagName = "svg";
  child.tagName = "path";
  child.closest = (selector) => (selector === "svg" ? parent : null);
  await fire("mousemove");
  assert.match(overlays[1].textContent, /^svg/);
  await fire("click");
  assert.deepEqual(copied, ["svg"]);

  const direct = fixture();
  direct.parent.tagName = "svg";
  direct.child.closest = (selector) =>
    selector === "svg" ? direct.parent : null;
  await direct.fire("click");
  assert.deepEqual(direct.copied, ["svg"]);
});

test("normal clicks are not intercepted", async () => {
  const { fire, copied } = fixture();
  const event = await fire("click", { altKey: false });
  assert.equal(event.defaultPrevented, undefined);
  assert.deepEqual(copied, []);
});

test("highlight uses the top-layer host and clears a disconnected selection", async () => {
  const { fire, overlays, parent, child } = fixture();
  child.closest = (selector) => (selector === "svg" ? null : parent);
  await fire("mousemove");
  assert.equal(overlays[0].parentNode, parent);
  child.isConnected = false;
  await fire("scroll");
  assert.equal(overlays[0].style.display, "none");
});
