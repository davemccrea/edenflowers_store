import assert from "node:assert/strict";
import { test } from "node:test";
import {
  elementReference,
  findHeexSource,
  selectorFor,
} from "../../assets/js/dev_element_reference.mjs";

const comment = (text) => ({ nodeType: 8, nodeValue: text });
const element = (tag, attrs = {}) => ({
  nodeType: 1,
  tagName: tag.toUpperCase(),
  id: attrs.id || "",
  children: [],
  getAttribute: (name) => attrs[name] ?? null,
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
  const target = element("button", { "data-phx-loc": "105" });
  append(root, entry, call, button, target);
  const document = {
    location: { href: "http://app.localhost/orders" },
  };
  return { root, target, document };
};

test("copies a terse element description, URL, selector, source, and component tree", () => {
  globalThis.CSS = { escape: (value) => value };
  const { target, document } = fixture();
  const result = elementReference(target, document);
  assert.equal(
    result,
    `Page: http://app.localhost/orders
Element: button
Selector: #orders > button
Source: lib/components.ex:105
Called from: lib/app.ex:20 (Components.button)
Entrypoint: App.render`,
  );
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
  const result = elementReference(second, document);
  assert.ok(result.includes("div > button:nth-of-type(2)"));
  assert.ok(!result.includes("Source:"));
  assert.equal(findHeexSource(second), null);
});

test("unannotated children keep their own selector and identify ancestor source", () => {
  const { target, document } = fixture();
  const child = element("span", {
    "aria-label": "Add item",
    "phx-click": "add",
  });
  child.textContent = "  Add   <item>  ";
  append(target, child);
  const result = elementReference(child, document);
  assert.ok(result.includes("#orders > button > span"));
  assert.ok(result.includes("nearest annotated ancestor"));
  assert.ok(result.includes("lib/components.ex:105"));
  assert.ok(!result.includes(":null"));
  assert.ok(result.includes('aria-label="Add item" phx-click="add"'));
  assert.ok(result.includes('Text: "Add <item>"'));
});

test("descriptions bound text and omit form values", () => {
  const { document } = fixture();
  const input = element("input", { type: "password", value: "secret" });
  input.textContent = "x".repeat(500);
  const result = elementReference(input, document);
  assert.ok(!result.includes("secret"));
  assert.ok(result.includes(`${"x".repeat(117)}...`));
  assert.ok(!result.includes("x".repeat(121)));
});

test("selectors skip LiveView's generated root id so they survive a reload", () => {
  globalThis.CSS = { escape: (value) => value };
  const body = element("body");
  const root = element("div", { id: "phx-GOKCZQoxJwRGIn6h" });
  const footer = element("footer");
  append(body, root);
  append(root, footer);

  assert.equal(selectorFor(footer), "body > div > footer");
});
