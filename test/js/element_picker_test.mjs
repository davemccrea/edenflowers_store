import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const picker = readFileSync(
  new URL("../../assets/js/element_picker.js", import.meta.url),
  "utf8",
).replace(/^import [^;]*;\n/m, "");

const fixture = ({
  dev = true,
  reviewer = false,
  touch = false,
  responses = {},
  fetchReply = null,
} = {}) => {
  const listeners = new Map();
  const overlays = [];
  const copied = [];
  const requests = [];
  const observers = [];
  const location = { pathname: "/fi/kauppa", search: "" };
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
    style: {
      properties: {},
      setProperty(name, value) {
        this.properties[name] = value;
      },
      removeProperty(name) {
        delete this.properties[name];
      },
      getPropertyValue(name) {
        return this.properties[name] ?? "";
      },
    },
    open: false,
    showPopover() {
      this.open = true;
    },
    hidePopover() {
      this.open = false;
    },
    matches(selector) {
      return selector === ":popover-open" && this.open;
    },
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
    head: element("head"),
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
    location,
    fetch: async (url, options = {}) => {
      requests.push({
        url,
        method: options.method,
        body: options.body && JSON.parse(options.body),
      });
      if (fetchReply) {
        const reply = fetchReply(url, options);
        if (reply) return reply;
      }
      return { ok: true, json: async () => responses[url.split("?")[0]] ?? [] };
    },
    matchMedia: () => ({ matches: touch }),
    confirm: () => true,
    getComputedStyle: (node) => ({
      getPropertyValue: (name) => node.style.getPropertyValue(name),
    }),
    MutationObserver: class {
      constructor(callback) {
        this.callback = callback;
        observers.push(this);
      }
      observe(target) {
        this.target = target;
      }
      disconnect() {
        this.disconnected = true;
      }
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
  return {
    fire,
    copied,
    overlays,
    parent,
    child,
    body,
    listeners,
    requests,
    observers,
    location,
  };
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
  assert.match(overlays[2].textContent, /^button/);
  await fire("mousemove");
  assert.match(overlays[2].textContent, /^button/);
  await fire("keydown", { key: "ArrowDown" });
  assert.match(overlays[2].textContent, /^span/);
  await fire("keydown", { key: "ArrowUp" });
  await fire("click");
  assert.deepEqual(copied, ["BUTTON"]);
  assert.equal(overlays[3].textContent, "✓ Copied");
  assert.match(overlays[2].textContent, /^button/);
});

test("popup keeps element identity and controls terse", async () => {
  const { fire, overlays, child } = fixture();
  child.id = "add-to-cart";
  child.classList = ["unnecessary-class"];
  await fire("mousemove");
  assert.equal(overlays[2].textContent, "span#add-to-cart · no source");
  assert.equal(overlays[3].textContent, "⌥↑ parent · ⌥↓ child · ⌥click copy");
});

test("SVG internals select the SVG itself, including on direct click", async () => {
  const { fire, copied, overlays, parent, child } = fixture();
  parent.tagName = "svg";
  child.tagName = "path";
  child.closest = (selector) => (selector === "svg" ? parent : null);
  await fire("mousemove");
  assert.match(overlays[2].textContent, /^svg/);
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

test("highlight joins the open modal and anchors to the element", async () => {
  const { fire, overlays, parent, child } = fixture();
  child.closest = (selector) => (selector === "svg" ? null : parent);
  await fire("mousemove");
  const [highlight] = overlays.filter(
    (node) => node.className === "ep-highlight",
  );
  assert.equal(highlight.parentNode, parent);
  assert.ok(highlight.open);
  const name = highlight.style.getPropertyValue("position-anchor");
  assert.match(name, /^--element-picker-/);
  assert.equal(child.style.getPropertyValue("anchor-name"), name);

  await fire("keyup", { key: "Alt" });
  assert.ok(!highlight.open);
  assert.equal(child.style.getPropertyValue("anchor-name"), "");
});

test("a reviewer on a page without dev annotations gets a note box, not a copy", async () => {
  const { fire, copied, overlays } = fixture({ dev: false, reviewer: true });
  const event = await fire("click");
  assert.deepEqual(copied, []);
  assert.ok(event.defaultPrevented);
  assert.ok(overlays.some((node) => node.tagName === "TEXTAREA"));
});

test("on a touch screen, review mode turns a plain tap into a note box", async () => {
  const { fire, overlays } = fixture({
    dev: false,
    reviewer: true,
    touch: true,
  });
  const toggle = overlays.find((node) => node.textContent === "✎");

  const before = await fire("click", { altKey: false });
  assert.ok(!before.defaultPrevented);

  toggle.on.click();
  const tap = await fire("click", { altKey: false });
  assert.ok(tap.defaultPrevented);
  assert.ok(overlays.some((node) => node.tagName === "TEXTAREA"));
});

test("a reviewer in dev keeps their clipboard until they ask for the reference", async () => {
  const { fire, copied, overlays } = fixture({ reviewer: true });
  await fire("click");
  assert.deepEqual(copied, []);
  assert.ok(overlays.some((node) => node.tagName === "TEXTAREA"));
  await overlays.find((node) => node.title === "Copy ref").on.click();
  assert.deepEqual(copied, ["SPAN"]);
});

test("shortcut hints sit outside the wrapping button row", async () => {
  const { fire, overlays } = fixture({ reviewer: true });
  await fire("click");
  const form = overlays.find((node) => node.tagName === "FORM");
  const copy = overlays.find((node) => node.title === "Copy ref");
  const status = overlays.find((node) =>
    node.textContent?.includes("⌘↵ to copy"),
  );
  assert.equal(status.parentNode, form);
  assert.notEqual(copy.parentNode, form);
  assert.equal(copy.parentNode.style.flexWrap, "wrap");
  assert.equal(copy.parentNode.style.justifyContent, "flex-end");
});

test("Copy ref includes the current message without saving the note", async () => {
  const { fire, copied, overlays, requests } = fixture({ reviewer: true });
  await fire("click");
  const textarea = overlays.find((node) => node.tagName === "TEXTAREA");
  const copy = overlays.find((node) => node.title === "Copy ref");
  textarea.value = "  Make this larger\nKeep the colour  ";
  await copy.on.click();
  assert.deepEqual(copied, ["SPAN\n\nMake this larger\nKeep the colour"]);
  textarea.value = "Updated message";
  await copy.on.click();
  assert.equal(copied[1], "SPAN\n\nUpdated message");
  assert.ok(!requests.some((request) => request.url === "/review-notes"));
});

for (const modifier of ["metaKey", "ctrlKey"]) {
  test(`${modifier}+Enter copies the reference and message instead of saving`, async () => {
    const { fire, copied, overlays } = fixture({ reviewer: true });
    await fire("click");
    overlays.find((node) => node.tagName === "TEXTAREA").value =
      "Make it larger";
    const form = overlays.find((node) => node.tagName === "FORM");
    let saves = 0;
    form.requestSubmit = () => saves++;
    let prevented = false;
    await form.on.keydown({
      key: "Enter",
      [modifier]: true,
      preventDefault() {
        prevented = true;
      },
      stopPropagation() {},
    });
    assert.ok(prevented);
    assert.deepEqual(copied, ["SPAN\n\nMake it larger"]);
    assert.equal(saves, 0);

    await form.on.keydown({
      key: "Enter",
      [modifier]: true,
      preventDefault() {},
      stopPropagation() {},
    });
    assert.equal(saves, 0);
    assert.equal(copied.length, 2);

    prevented = false;
    await form.on.keydown({
      key: "s",
      [modifier]: true,
      preventDefault() {
        prevented = true;
      },
      stopPropagation() {},
    });
    assert.ok(prevented);
    assert.equal(saves, 1);
  });
}

test("the copy shortcut is unavailable outside dev", async () => {
  const { fire, copied, overlays } = fixture({ dev: false, reviewer: true });
  await fire("click");
  const form = overlays.find((node) => node.tagName === "FORM");
  form.requestSubmit = () => assert.fail("must not save");
  await form.on.keydown({
    key: "Enter",
    metaKey: true,
    preventDefault() {},
    stopPropagation() {},
  });
  assert.deepEqual(copied, []);
});

test("Copy ref omits whitespace-only messages", async () => {
  const { fire, copied, overlays } = fixture({ reviewer: true });
  await fire("click");
  overlays.find((node) => node.tagName === "TEXTAREA").value = " \n ";
  await overlays.find((node) => node.title === "Copy ref").on.click();
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
  assert.equal(text.parentNode.className, "ep-note");
  assert.ok(text.parentNode.open);
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
    method: "PATCH",
    body: { body: "Use ni, not du" },
  });
});

test("I can delete my own note from its box, and only my own", async () => {
  const notes = {
    "/review-notes": [
      { id: "n1", body: "Use ni here", selector: "#noted", "mine?": true },
    ],
  };
  const mine = fixture({ dev: false, reviewer: true, responses: notes });
  await mine.fire("click", { target: mine.parent });
  const remove = mine.overlays.find((node) => node.title === "Delete");
  await remove.on.click();
  assert.deepEqual(mine.requests.at(-1), {
    url: "/review-notes/n1",
    method: "DELETE",
    body: {},
  });

  const fresh = fixture({ dev: false, reviewer: true });
  await fresh.fire("click");
  const form = fresh.overlays.find((node) => node.tagName === "FORM");
  assert.ok(
    !fresh.overlays.some((node) => node.title === "Delete" && node.parentNode),
  );
  assert.ok(form);
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

const deferred = () => {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
};

const flush = () => new Promise(setImmediate);

test("released anchors disconnect only their observer and preserve patched names", async () => {
  const { fire, parent, child, observers } = fixture();
  child.style.setProperty("anchor-name", "--original");
  await fire("mousemove");
  const name = child.style.getPropertyValue("anchor-name").split(", ")[1];
  child.style.setProperty("anchor-name", "--patched");
  observers[0].callback();
  assert.equal(
    child.style.getPropertyValue("anchor-name"),
    `--patched, ${name}`,
  );
  await fire("mousemove", { target: parent });
  assert.equal(child.style.getPropertyValue("anchor-name"), "--patched");
  assert.equal(observers[0].disconnected, true);
  assert.equal(observers[1].disconnected, undefined);
  await fire("keyup", { key: "Alt" });
  assert.equal(observers[1].disconnected, true);
  assert.ok(!Object.hasOwn(parent.style.properties, "anchor-name"));
});

for (const action of ["save", "delete"]) {
  test(`a stale ${action} reply leaves the newer box open`, async () => {
    const reply = deferred();
    const f = fixture({
      dev: false,
      reviewer: true,
      responses: {
        "/review-notes": [
          { id: "n1", body: "Old note", selector: "#noted", "mine?": true },
        ],
      },
      fetchReply: (url) => url === "/review-notes/n1" && reply.promise,
    });
    await f.fire("click", { target: f.parent });
    const first = f.overlays.find((node) => node.tagName === "FORM");
    const pending =
      action === "save"
        ? first.on.submit({ preventDefault() {} })
        : f.overlays.find((node) => node.title === "Delete").on.click();
    await f.fire("click");
    const second = f.overlays.filter((node) => node.tagName === "FORM").at(-1);
    let removed = false;
    second.remove = () => {
      removed = true;
    };
    reply.resolve({ ok: true });
    await pending;
    assert.equal(removed, false);
    assert.ok(!f.overlays.some((node) => /^✓ Note/.test(node.textContent)));
  });
}

test("a submitted note still saves when its box closes before its strings arrive", async () => {
  const strings = deferred();
  const f = fixture({
    dev: false,
    reviewer: true,
    fetchReply: (url) => url === "/review-notes/strings" && strings.promise,
  });
  await f.fire("click");
  f.overlays.find((node) => node.tagName === "TEXTAREA").value = "New note";
  const pending = f.overlays
    .find((node) => node.tagName === "FORM")
    .on.submit({ preventDefault() {} });
  await f.fire("pointerdown", { altKey: false });
  strings.resolve({ ok: true, json: async () => [] });
  await pending;
  assert.ok(f.requests.some((request) => request.url === "/review-notes"));
});

test("only the latest pending selection opens a box", async () => {
  const notes = deferred();
  const f = fixture({
    dev: false,
    reviewer: true,
    fetchReply: (url) => url.startsWith("/review-notes?") && notes.promise,
  });
  const first = f.fire("click");
  const second = f.fire("click", { target: f.parent });
  notes.resolve({ ok: true, json: async () => [] });
  await Promise.all([first, second]);
  assert.equal(f.overlays.filter((node) => node.tagName === "FORM").length, 1);
  assert.ok(f.overlays.some((node) => node.textContent === "button"));
});

for (const action of ["notes", "pick"]) {
  test(`pending ${action} does not render after a page change`, async () => {
    const notes = deferred();
    const f = fixture({
      dev: false,
      reviewer: true,
      fetchReply: (url) => url.startsWith("/review-notes?") && notes.promise,
    });
    const pending =
      action === "notes" ? f.fire("keydown", { key: "Alt" }) : f.fire("click");
    f.location.pathname = "/fi/other";
    notes.resolve({
      ok: true,
      json: async () => [{ body: "Old page", selector: "#noted" }],
    });
    await pending;
    await flush();
    assert.ok(
      !f.overlays.some(
        (node) => node.className === "ep-note" || node.className === "ep-box",
      ),
    );
  });
}
