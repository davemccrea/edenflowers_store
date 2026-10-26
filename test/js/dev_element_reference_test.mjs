import assert from "node:assert/strict";
import { test } from "node:test";
import {
  elementReference,
  findHeexSource,
} from "../../assets/js/dev_element_reference.mjs";

const comment = (text) => ({ nodeType: 8, nodeValue: text });
const element = (tag, attrs = {}, text = "") => ({
  nodeType: 1,
  tagName: tag.toUpperCase(),
  id: attrs.id || "",
  textContent: text,
  children: [],
  getAttribute: (name) => attrs[name] ?? null,
  hasAttribute: (name) => name in attrs,
});
const append = (parent, ...nodes) => {
  for (const node of nodes) {
    node.previousSibling = parent.lastChild;
    node.parentNode = parent;
    node.parentElement = parent.nodeType === 1 ? parent : null;
    parent.lastChild = node;
    if (node.nodeType === 1) parent.children.push(node);
  }
};
const fixture = () => {
  const root = element("main", { id: "orders" });
  const entry = comment(" <App.render> lib/app.ex:10 (app) ");
  const call = comment(" @caller lib/app.ex:20 (app) ");
  const button = comment(" <Components.button> lib/components.ex:100 (app) ");
  const target = element("button", { "data-phx-loc": "105" }, "Save");
  append(root, entry, call, button, target);
  const comments = [entry, call, button];
  const document = {
    location: { href: "http://app.localhost/orders" },
    createTreeWalker: () => {
      let index = 0;
      return { nextNode: () => comments[index++] ?? null };
    },
    querySelectorAll: () => [],
  };
  return { root, target, document };
};

test("copies Tidewave-style context and rendering details without a user prompt", () => {
  globalThis.CSS = { escape: (value) => value };
  const { target, document } = fixture();
  const result = elementReference(target, document);
  assert.ok(result.startsWith('<context name="current-page">'));
  assert.ok(!result.includes("user_prompt"));
  assert.ok(result.includes("entrypoint: App.render\nsource: lib/app.ex:10"));
  assert.ok(result.includes("<selector>\n#orders > button\n</selector>"));
  assert.ok(
    result.includes("The element source is at:\n\nlib/components.ex:105"),
  );
  assert.ok(
    result.includes("lib/app.ex:20: Components.button\nentrypoint: App.render"),
  );
  assert.ok(result.includes("Components.button: lib/components.ex:100"));
  assert.ok(result.includes("<text-content>\nSave\n</text-content>"));
});

test("slot content uses the caller file and skips completed sibling components", () => {
  const { root, target } = fixture();
  const slot = comment(" <:inner_block> lib/app.ex:20 (app) ");
  const sibling = comment(" <Components.icon> lib/icons.ex:5 (app) ");
  const close = comment(" </Components.icon> ");
  root.lastChild = target.previousSibling;
  root.children = [];
  append(root, slot, sibling, close, target);
  const source = findHeexSource(target);
  assert.equal(source.location, "lib/app.ex:105");
  assert.equal(source.component, "Components.button");
  assert.ok(!source.components.some(({ name }) => name === "Components.icon"));
});

test("selectors distinguish repeated tags without IDs and missing annotations still copy", () => {
  const root = element("div");
  const first = element("button");
  const second = element("button");
  append(root, first, second);
  const { document } = fixture();
  document.createTreeWalker = () => ({ nextNode: () => null });
  const result = elementReference(second, document);
  assert.ok(result.includes("div > button:nth-of-type(2)"));
  assert.ok(!result.includes("framework-details"));
  assert.equal(findHeexSource(second), null);
});

test("includes live view runtime details when available", () => {
  const { target, document } = fixture();
  document.querySelectorAll = () => [
    element("div", {
      id: "phx-1",
      "data-phx-main": "",
      "data-phx-pid": "<0.123.0>",
    }),
  ];
  assert.ok(
    elementReference(target, document).includes(
      "* Main LiveView #phx-1 with PID <0.123.0>",
    ),
  );
});
