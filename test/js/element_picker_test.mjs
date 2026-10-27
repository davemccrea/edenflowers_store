import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const picker = readFileSync(
  new URL("../../assets/js/element_picker.js", import.meta.url),
  "utf8",
).replace(/^import [^;]*;\n/, "");

const fixture = ({ dev = true, reviewer = false, responses = {} } = {}) => {
  const listeners = new Map();
  const overlays = [];
  const copied = [];
  const requests = [];
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
    hasAttribute: () => reviewer,
    setAttribute() {},
    on: {},
    addEventListener(name, callback) {
      this.on[name] = callback;
    },
    focus() {},
    remove() {},
    contains: () => false,
    querySelectorAll: () => [],
    replaceWith() {},
    innerText: "Lisää ostoskoriin",
    outerHTML: "",
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
    documentElement: { lang: "fi" },
    querySelector: (selector) => {
      if (selector === "[data-phx-loc]") return dev ? parent : null;
      if (selector === "#noted") return parent;
      if (selector.startsWith("meta")) return { content: "token" };
      return null;
    },
    createTreeWalker: () => ({ nextNode: () => false }),
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
    selectorFor: () => "",
    NodeFilter: { SHOW_TEXT: 4 },
    location: { pathname: "/fi/kauppa", search: "" },
    fetch: async (url, options = {}) => {
      requests.push({ url, body: options.body && JSON.parse(options.body) });
      return { ok: true, json: async () => responses[url.split("?")[0]] ?? [] };
    },
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
  return { fire, copied, overlays, parent, child, body, listeners, requests };
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

test("a reviewer on a page without dev annotations gets a note box, not a copy", async () => {
  const { fire, copied, overlays } = fixture({ dev: false, reviewer: true });
  const event = await fire("click");
  assert.deepEqual(copied, []);
  assert.ok(event.defaultPrevented);
  assert.ok(overlays.some((node) => node.tagName === "TEXTAREA"));
});

test("a reviewer in dev keeps their clipboard until they ask for the reference", async () => {
  const { fire, copied, overlays } = fixture({ reviewer: true });
  await fire("click");
  assert.deepEqual(copied, []);
  assert.ok(overlays.some((node) => node.tagName === "TEXTAREA"));
  await overlays.find((node) => node.textContent === "Copy ref").on.click();
  assert.deepEqual(copied, ["SPAN"]);
});

test("a customer on a page without dev annotations gets nothing", async () => {
  const { fire, listeners } = fixture({ dev: false });
  const event = await fire("click");
  assert.equal(listeners.size, 0);
  assert.equal(event.defaultPrevented, undefined);
});

test("a reviewer's box looks up the element's strings and saves them with the note", async () => {
  const strings = [
    {
      domain: "storefront",
      msgctxt: null,
      msgid: "Add to cart",
      translations: {
        en: "Add to cart",
        fi: "Lisää ostoskoriin",
        sv: "Lägg i varukorgen",
      },
    },
  ];
  const { fire, overlays, requests } = fixture({
    dev: false,
    reviewer: true,
    responses: { "/review-notes/strings": strings },
  });
  await fire("click");
  const request = (url) => requests.find((sent) => sent.url === url);
  assert.deepEqual(request("/review-notes/strings").body, {
    texts: ["Lisää ostoskoriin"],
    locale: "fi",
  });

  overlays.find((node) => node.tagName === "TEXTAREA").value = "Too long";
  await overlays
    .find((node) => node.tagName === "FORM")
    .on.submit({ preventDefault() {} });
  assert.deepEqual(request("/review-notes").body.strings, [
    { domain: "storefront", msgctxt: null, msgid: "Add to cart" },
  ]);
});

test("holding Option outlines the page's open notes with their text", async () => {
  const { fire, overlays, requests } = fixture({
    dev: false,
    reviewer: true,
    responses: {
      "/review-notes": [{ body: "Use ni here", selector: "#noted" }],
    },
  });
  await fire("keydown", { key: "Alt" });
  await new Promise(setImmediate);
  assert.equal(requests[0].url, "/review-notes?path=%2Ffi%2Fkauppa");
  const text = overlays.find((node) => node.textContent === "Use ni here");
  assert.ok(text.parentNode.style.border.includes("dashed"));
});

test("Option+Clicking an element with my note opens it for editing", async () => {
  const { fire, overlays, requests, parent } = fixture({
    dev: false,
    reviewer: true,
    responses: {
      "/review-notes": [
        { id: "n1", body: "Use ni here", selector: "#noted", "mine?": true },
      ],
    },
  });
  await fire("click", { target: parent });
  const textarea = overlays.find((node) => node.tagName === "TEXTAREA");
  assert.equal(textarea.value, "Use ni here");

  textarea.value = "Use ni, not du";
  await overlays
    .find((node) => node.tagName === "FORM")
    .on.submit({ preventDefault() {} });
  assert.deepEqual(requests.at(-1), {
    url: "/review-notes/n1",
    body: { body: "Use ni, not du" },
  });
});

test("a click outside the note box cancels it", async () => {
  const { fire, overlays } = fixture({ dev: false, reviewer: true });
  await fire("click");
  const form = overlays.find((node) => node.tagName === "FORM");
  let removed = false;
  form.remove = () => (removed = true);
  await fire("pointerdown", { altKey: false });
  assert.ok(removed);
});
